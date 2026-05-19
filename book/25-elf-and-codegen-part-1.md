# Chapter 25 — ELF Emission and Codegen, Part 1: Instructions

> **Status:** ✅ complete.  Tangles `080-cc-elf.fth` byte-identically
> and contributes the first half of `090-cc-emit.fth` (lines 1–411).

## Goal

By the end of this chapter the reader can:

- read `080-cc-elf.fth` and explain how the output ELF's header is
  laid out, what fields are back-patched, and why one PT_LOAD
  segment suffices;
- read the first half of `090-cc-emit.fth` — the per-instruction
  encoders (push/pop, load/store, arithmetic, compares, branches)
  — and predict the bytes each emits;
- explain the calling-convention assignment of registers
  (`rdi` = current expression result, `rcx` = right-operand temp,
  `rbp` = frame base).

## Source coverage

`080-cc-elf.fth` (68 lines) — entire file.
`090-cc-emit.fth` lines 1–411 (file header through `cc-patch-rel32-
to-here`).  The remaining lines 412–1027 are covered in Ch 26.

## Concepts introduced

- **One-segment output ELF.**  Like the seed, the C compiler emits
  a single R-W-X PT_LOAD at `0x400000`, entry at `0x400078`.  The
  64-byte ELF header + 56-byte program header = 120 bytes of
  preamble before any code.
- **Back-patched `p_filesz` / `p_memsz`.**  Cursor positions at
  file offsets 96 and 104 are zero on the first pass and
  overwritten via `cc-out-patch-4le` once codegen finishes.
- **Per-instruction Forth words.**  Each x86-64 instruction the
  compiler emits has its own `cc-emit-*` word; the higher-level
  passes never touch raw bytes.
- **Register convention.**  `rdi` carries the current expression
  result; `rcx` holds the right operand of a binary op; `rax` is
  used for `idiv` and SYS-V return values; `rbp` is the frame
  pointer.
- **`rel32` placeholders + `cc-patch-rel32-to-here`.**  The codegen
  emits a zero rel32 alongside its conditional jump, returns the
  byte offset of that rel32, and patches it later when the branch
  target is known — the same fixup-on-the-stack technique we saw
  in Forth's `if,` (Ch 11), now applied to ELF bytes.

## Concepts carried in

- `cc-emit-byte`, `cc-emit-4le`, `cc-emit-8le`, `cc-out-patch-4le`,
  `cc-out-pos` (Ch 21).
- ELF64 ehdr + phdr layout (Ch 13 covers the seed's variant).
- x86-64 instruction encoding intuition (Chs 14–16, 18).

## Concepts deferred

- The frame-aware encoders (prologue, epilogue, local-variable
  load/store, param spills, function calls) — Ch 26.
- Libc shims (`putchar`, `exit`, `getchar`, `fputs`, `fputc`,
  `fopen`, `fclose`, `fwrite`, `fread`, `calloc`, `free`) — Ch 26.
- Globals + global-vaddr fixups — Ch 26.
- The string-literal escape decoder — Ch 26.

---

We left Ch 24 with a compiler that knows what types and symbols
exist, but not how to emit a single byte of machine code.  This
chapter and the next are about the *output side*: how bytes leave
the compiler.

`080-cc-elf.fth` writes the ELF wrapper.  Sixty-eight lines, two
entry points (`cc-emit-elf-header`, `cc-finalize-elf`), one
assumption: the output is a single R-W-X PT_LOAD, exactly like
the seed.  That choice is the reason the compiler is so small —
no `e_shoff` table, no separate read-only segment, no relocation
records.

`090-cc-emit.fth` is the bigger of the pair: 1027 lines of
instruction encoders.  Each is a Forth word that writes the exact
bytes of one (or a few) x86-64 instructions into `cc-out-buf`.
This chapter covers the first half — the primitive encoders that
don't know about frames.  Ch 26 covers the rest.

## 1. `080-cc-elf.fth`: the ELF wrapper

```forth file=080-cc-elf.fth
\ 080-cc-elf.fth — ELF64 header + program header emission for our compiled output.
\
\ Layout: 64-byte ELF64_Ehdr + 56-byte Elf64_Phdr (one PT_LOAD) = 120 bytes.
\ Code begins at vaddr 0x400078, file offset 120.
\
\ Depends on 030-cc-io.fth (cc-emit-byte, cc-emit-4le, cc-emit-8le, cc-out-pos,
\ cc-out-patch-4le).

[lit] 4194304 constant cc-base-vaddr            \ 0x400000
[lit] 4194424 constant cc-entry-vaddr           \ 0x400078

\ p_filesz lives at file offset 96, 8 bytes LE.
\ p_memsz lives at file offset 104.
[lit] 96 constant cc-filesz-offset
[lit] 104 constant cc-memsz-offset

\ cc-emit-elf-header ( -- )  Emit the 120-byte header at start of cc-out-buf.
\ p_filesz left at 0 (patched in cc-finalize-elf).
: cc-emit-elf-header
  \ e_ident: 7F 45 4C 46 (magic), class=2, data=1, version=1, osabi=0, pad=8
  [lit] 127 cc-emit-byte [lit]  69 cc-emit-byte
  [lit]  76 cc-emit-byte [lit]  70 cc-emit-byte
  [lit]   2 cc-emit-byte [lit]   1 cc-emit-byte [lit]   1 cc-emit-byte
  [lit]   0 cc-emit-byte
  [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte
  [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte [lit]   0 cc-emit-byte
  \ e_type=2 (ET_EXEC), e_machine=0x3E (AMD64) — both 16-bit LE
  [lit] 2 cc-emit-byte [lit] 0 cc-emit-byte
  [lit] 62 cc-emit-byte [lit] 0 cc-emit-byte
  \ e_version (32-bit LE)
  [lit] 1 cc-emit-4le
  \ e_entry (64-bit LE) = 0x400078
  cc-entry-vaddr cc-emit-8le
  \ e_phoff = 64
  [lit] 64 cc-emit-8le
  \ e_shoff = 0
  [lit] 0 cc-emit-8le
  \ e_flags
  [lit] 0 cc-emit-4le
  \ e_ehsize=64, e_phentsize=56, e_phnum=1, then 6 bytes of zero
  [lit] 64 cc-emit-byte [lit] 0 cc-emit-byte
  [lit] 56 cc-emit-byte [lit] 0 cc-emit-byte
  [lit]  1 cc-emit-byte [lit] 0 cc-emit-byte
  [lit]  0 cc-emit-byte [lit] 0 cc-emit-byte
  [lit]  0 cc-emit-byte [lit] 0 cc-emit-byte
  [lit]  0 cc-emit-byte [lit] 0 cc-emit-byte
  \ Program header (56 bytes, one PT_LOAD):
  [lit] 1 cc-emit-4le                            \ p_type = PT_LOAD
  [lit] 7 cc-emit-4le                            \ p_flags = R|W|X
  [lit] 0 cc-emit-8le                            \ p_offset = 0
  cc-base-vaddr cc-emit-8le                      \ p_vaddr = 0x400000
  cc-base-vaddr cc-emit-8le                      \ p_paddr = 0x400000
  [lit] 0 cc-emit-8le                            \ p_filesz (patched later)
  [lit] 81920 cc-emit-8le                        \ p_memsz = 0x14000
  [lit] 4096 cc-emit-8le ;                       \ p_align = 0x1000

\ cc-finalize-elf ( -- )  After codegen, patch p_filesz to current cc-out-pos.
\ We patch only the low 4 bytes — our outputs are well under 4 GiB and the
\ high 4 bytes were already emitted as zero.  Also bump p_memsz so it is at
\ least p_filesz (otherwise large outputs like the M2-Planet monolith — well
\ past the 0x14000 default — produce an invalid ELF that the kernel won't
\ load correctly).  Keep the 0x14000 minimum for small outputs that need
\ BSS-style headroom past their file image.
: cc-finalize-elf
  cc-out-pos @ cc-filesz-offset cc-out-patch-4le
  cc-out-pos @ [lit] 81920 > if,
    cc-out-pos @ cc-memsz-offset cc-out-patch-4le
  then, ;
```

Two constants, four magic-number offsets, two functions.  That's
the whole ELF layer.

The output's *vaddr layout* is identical to the seed's: base at
`0x400000` (Linux's traditional ELF load address), entry at
`0x400078` (right past the 120-byte ehdr+phdr block).  The single
PT_LOAD segment maps file bytes 0 through `p_filesz` to vaddrs
`0x400000` through `0x400000 + p_filesz`, with `p_memsz` bytes of
zero-extended memory available past the file image — the same
BSS-style headroom the seed uses.

The flag combination `R|W|X = 7` is what makes this a *self-
modifying* binary: code and data live in the same segment so the
compiler doesn't need a separate `.data` phdr.  This is wasteful by
modern standards (the kernel can't mark code pages read-only), but
it costs one phdr instead of two — a 56-byte saving plus the
simplicity of one cursor for both code and data.

`cc-emit-elf-header` writes the 120 bytes top-to-bottom, with all
the magic numbers literal in the source.  Read it once and the
field-by-field correspondence to `Elf64_Ehdr` is obvious:
`e_ident` (16 bytes of identification), `e_type` (2), `e_machine`
(2), `e_version` (4), `e_entry` (8), `e_phoff` (8), `e_shoff` (8,
zeroed because we have no section headers), `e_flags` (4),
`e_ehsize` (2), `e_phentsize` (2), `e_phnum` (2), then 6 zeroed
bytes of `e_shentsize/e_shnum/e_shstrndx`.

The program header at file offset 64 is similarly transparent:
`p_type = PT_LOAD = 1`, `p_flags = R|W|X = 7`, then `p_offset`,
`p_vaddr`, `p_paddr`, `p_filesz`, `p_memsz`, `p_align`.

`p_filesz` is the one field we *can't* know at header-emit time —
it's the total file size, but we haven't generated the code yet.
The trick is the same as Ch 21's back-patching: emit `0` now,
remember the offset (96), patch it in `cc-finalize-elf` once we
know `cc-out-pos`.

`p_memsz` defaults to `81920 = 0x14000`, giving 80 KiB of
zero-initialized BSS-style space past the code image for the
compiler's own globals.  The `if` in `cc-finalize-elf` bumps it to
match `p_filesz` for outputs *larger* than 80 KiB — the M2-Planet
monolith is well over a megabyte and would otherwise produce an
invalid ELF the kernel refuses.

## 2. `090-cc-emit.fth`, part 1: register convention

```forth file=090-cc-emit.fth
\ 090-cc-emit.fth — code-emission helpers for the C-subset compiler.
\ Builds tiny instruction-encoders on top of cc-emit-byte / cc-emit-4le from
\ 030-cc-io.fth.  All output goes to cc-out-buf; nothing here touches the seed's
\ HERE pointer.
\
\ Register convention for the compiled code:
\   rdi  — scratch / current expression result
\   rcx  — temp for binary-op right operand
\   rax  — used by idiv (low quotient/remainder); also by SYS-V return
\   rbp  — frame base; locals at [rbp - 8*(slot+1)]
\
\ Depends on 030-cc-io.fth (cc-emit-byte, cc-emit-4le).

\ ===========================================================================
\ Immediate-load instructions (REX.W + C7 /0 + imm32)
\ ===========================================================================

\ cc-emit-mov-rdi-imm32 ( v -- )   48 C7 C7 <imm32>
: cc-emit-mov-rdi-imm32
  [lit]  72 cc-emit-byte
  [lit] 199 cc-emit-byte
  [lit] 199 cc-emit-byte
  cc-emit-4le ;

\ ===========================================================================
\ Stack ops
\ ===========================================================================

\ push rdi: 0x57
: cc-emit-push-rdi  [lit]  87 cc-emit-byte ;

\ pop rdi:  0x5F
: cc-emit-pop-rdi   [lit]  95 cc-emit-byte ;

\ pop rsi:  0x5E
: cc-emit-pop-rsi   [lit]  94 cc-emit-byte ;

\ pop rdx:  0x5A
: cc-emit-pop-rdx   [lit]  90 cc-emit-byte ;

\ pop rcx:  0x59
: cc-emit-pop-rcx   [lit]  89 cc-emit-byte ;

\ pop r8:   0x41 0x58  (REX.B + pop)
: cc-emit-pop-r8    [lit]  65 cc-emit-byte [lit]  88 cc-emit-byte ;

\ pop r9:   0x41 0x59
: cc-emit-pop-r9    [lit]  65 cc-emit-byte [lit]  89 cc-emit-byte ;

\ push rbx (0x53) / pop rbx (0x5B).  Used by switch to preserve the outer
\ value of rbx across the switch (which uses rbx to hold the scrutinee).
: cc-emit-push-rbx  [lit]  83 cc-emit-byte ;
: cc-emit-pop-rbx   [lit]  91 cc-emit-byte ;

\ ===========================================================================
\ Local-variable access
\ ===========================================================================
\ Locals live at [rbp - 8*(slot+1)].  The compiler uses slots 0..15 so the
\ displacement fits in a signed disp8 (-128..-8).
\
\ cc-disp8-from-slot ( slot -- byte )
\   = (256 - 8*(slot+1)) AND 255 = the unsigned-byte representation of the
\   signed displacement -8*(slot+1).

: cc-disp8-from-slot
  [lit] 1 + [lit] 8 *                            \ 8 * (slot+1)
  [lit] 0 swap -                                  \ negate
  [lit] 255 and ;                                 \ low byte

\ mov rdi, [rbp + disp8]:  48 8B 7D <disp8>
: cc-emit-load-local                              ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 139 cc-emit-byte
  [lit] 125 cc-emit-byte
  cc-disp8-from-slot cc-emit-byte ;

\ mov [rbp + disp8], rdi:  48 89 7D <disp8>
: cc-emit-store-local                             ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 125 cc-emit-byte
  cc-disp8-from-slot cc-emit-byte ;

\ lea rdi, [rbp + disp8]:  48 8D 7D <disp8>
\ ModR/M(mod=01, reg=rdi=7, rm=rbp=5) = 0x7D.  Loads the *address* of the local
\ slot into rdi (used to implement `&local`).
: cc-emit-lea-rdi-local                           ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 141 cc-emit-byte
  [lit] 125 cc-emit-byte
  cc-disp8-from-slot cc-emit-byte ;

\ mov rdi, [rdi]:  48 8B 3F
\ ModR/M(mod=00, reg=rdi=7, rm=rdi=7) = 0x3F.  Loads the qword at the address
\ currently in rdi into rdi (dereference).
: cc-emit-load-via-rdi
  [lit]  72 cc-emit-byte
  [lit] 139 cc-emit-byte
  [lit]  63 cc-emit-byte ;

\ movzx rdi, BYTE PTR [rdi]:  48 0F B6 3F
\ Zero-extends a single byte from [rdi] into rdi.  Used by `s[i]` rvalue use
\ where s is `char*` (or any other byte-element access path).
: cc-emit-load-byte-via-rdi
  [lit]  72 cc-emit-byte
  [lit]  15 cc-emit-byte
  [lit] 182 cc-emit-byte
  [lit]  63 cc-emit-byte ;

\ mov [rcx], rdi:  48 89 39
\ ModR/M(mod=00, reg=rdi=7, rm=rcx=1) = 0x39.  Stores rdi to the qword address
\ in rcx (assignment via dereference).
: cc-emit-store-via-rcx
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit]  57 cc-emit-byte ;

\ mov BYTE PTR [rcx], dil:  40 88 39
\ Stores the low byte of rdi to [rcx].  REX=0x40 is needed to select dil
\ instead of bh.  Used by `s[i] = c;` where s is char*.
: cc-emit-store-byte-via-rcx
  [lit]  64 cc-emit-byte
  [lit] 136 cc-emit-byte
  [lit]  57 cc-emit-byte ;

\ shl rdi, imm8:  48 C1 E7 <imm8>
\ ModR/M(mod=11, reg=/4 = SHL, rm=rdi=7) = 11_100_111 = 0xE7.  Multiplies rdi
\ by 2^imm8 (used to scale array index by sizeof(T) when T is 8 bytes).
: cc-emit-shl-rdi-imm8                            ( imm8 -- )
  [lit]  72 cc-emit-byte
  [lit] 193 cc-emit-byte
  [lit] 231 cc-emit-byte
  cc-emit-byte ;

\ Convenience: rdi <<= 3 (multiply by 8 = sizeof(int)/sizeof(ptr)).
: cc-emit-shl-rdi-3   [lit] 3 cc-emit-shl-rdi-imm8 ;

\ add rdi, imm32:  48 81 C7 <imm32>
\ ModR/M(mod=11, reg=/0 = ADD, rm=rdi=7) = 11_000_111 = 0xC7.  Used to bias
\ a struct base/pointer in rdi by a field offset.  imm32 is sign-extended.
: cc-emit-add-rdi-imm32                           ( imm32 -- )
  [lit]  72 cc-emit-byte
  [lit] 129 cc-emit-byte
  [lit] 199 cc-emit-byte
  cc-emit-4le ;

\ Param-spill helpers: store the SYS-V argument register holding the i'th
\ argument into local slot i.  Each one is `mov [rbp + disp8], <reg>`.
\ ModR/M byte: mod=01 (disp8), rm=rbp(=5).  reg field varies per source reg.
\ REX byte is 48 (W only) for rsi/rdx/rcx, 4C (W+R) for r8/r9.
\
\   reg=rsi(6): 01_110_101 = 0x75
\   reg=rdx(2): 01_010_101 = 0x55
\   reg=rcx(1): 01_001_101 = 0x4D
\   reg=r8 (0 with R bit): 01_000_101 = 0x45
\   reg=r9 (1 with R bit): 01_001_101 = 0x4D

: cc-emit-store-local-from-rsi                    ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 117 cc-emit-byte                          \ 0x75
  cc-disp8-from-slot cc-emit-byte ;

: cc-emit-store-local-from-rdx                    ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit]  85 cc-emit-byte                          \ 0x55
  cc-disp8-from-slot cc-emit-byte ;

: cc-emit-store-local-from-rcx                    ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit]  77 cc-emit-byte                          \ 0x4D
  cc-disp8-from-slot cc-emit-byte ;

: cc-emit-store-local-from-r8                     ( slot -- )
  [lit]  76 cc-emit-byte                          \ REX.W+R = 0x4C
  [lit] 137 cc-emit-byte
  [lit]  69 cc-emit-byte                          \ 0x45
  cc-disp8-from-slot cc-emit-byte ;

: cc-emit-store-local-from-r9                     ( slot -- )
  [lit]  76 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit]  77 cc-emit-byte                          \ 0x4D
  cc-disp8-from-slot cc-emit-byte ;

\ mov rax, [rbp + disp8]:  48 8B 45 <disp8>
\ ModR/M(mod=01, reg=rax=0, rm=rbp=5) = 01_000_101 = 0x45.  Used to load a
\ function-pointer local into rax just before an indirect `call rax` — keeps
\ rdi/rsi/etc. (already loaded with SYS-V args) untouched.
: cc-emit-load-local-into-rax                     ( slot -- )
  [lit]  72 cc-emit-byte
  [lit] 139 cc-emit-byte
  [lit]  69 cc-emit-byte                          \ 0x45
  cc-disp8-from-slot cc-emit-byte ;

\ call rax:  FF D0   (no REX needed; rax = reg 0).
\ ModR/M(mod=11, reg=/2 = CALL r/m64, rm=rax=0) = 11_010_000 = 0xD0.
: cc-emit-call-rax
  [lit] 255 cc-emit-byte
  [lit] 208 cc-emit-byte ;

\ ===========================================================================
\ Register-to-register moves
\ ===========================================================================
\ ADD/SUB/IMUL r/m64, r64 has reg-field=src, rm-field=dst.  We use rdi as the
\ destination accumulator and rcx for the right-operand temp.

\ mov rcx, rdi:  48 89 F9     (89 /r, mod=11 reg=rdi=7 rm=rcx=1 -> 11_111_001 = F9)
: cc-emit-mov-rcx-rdi
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 249 cc-emit-byte ;

\ mov rax, rdi:  48 89 F8     (mod=11 reg=rdi=7 rm=rax=0 -> 11_111_000 = F8)
: cc-emit-mov-rax-rdi
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 248 cc-emit-byte ;

\ mov rdi, rax:  48 89 C7     (mod=11 reg=rax=0 rm=rdi=7 -> 11_000_111 = C7)
\ Used after a function call to transfer the SYS-V return value into our
\ scratch rdi so the rest of the expression machinery sees it.
: cc-emit-mov-rdi-rax
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 199 cc-emit-byte ;

\ mov rbx, rdi:  48 89 FB   (89 /r, mod=11 reg=rdi=7 rm=rbx=3 -> 11_111_011 = FB)
\ Used at switch entry to stash the scrutinee in a callee-saved register so
\ it survives across case-body codegen (including any function calls).
: cc-emit-mov-rbx-rdi
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 251 cc-emit-byte ;

\ cmp rbx, imm32:  48 81 FB <imm32>   (81 /7, mod=11 /7=111 rm=rbx=3 -> FB)
\ Used by switch dispatch to compare the saved scrutinee against each case
\ constant.  Sets ZF iff rbx == imm32.  imm32 is sign-extended to 64 bits.
: cc-emit-cmp-rbx-imm32                           ( v -- )
  [lit]  72 cc-emit-byte
  [lit] 129 cc-emit-byte
  [lit] 251 cc-emit-byte
  cc-emit-4le ;

\ xor rax, rax:  48 31 C0     (zero rax in 3 bytes; for implicit return).
: cc-emit-xor-rax-rax
  [lit]  72 cc-emit-byte
  [lit]  49 cc-emit-byte
  [lit] 192 cc-emit-byte ;

\ ===========================================================================
\ ALU on rdi using rcx as the right operand
\ ===========================================================================
\ The binary-op pattern emitted by the parser is:
\     <eval left>          ; rdi = left
\     push rdi
\     <eval right>         ; rdi = right
\     mov rcx, rdi         ; rcx = right
\     pop rdi              ; rdi = left
\     <op> rdi, rcx        ; rdi = left <op> right
\
\ ADD r/m64, r64 (0x01 /r): rm=dst, reg=src.
\   add rdi, rcx -> mod=11 reg=rcx=1 rm=rdi=7 -> 11_001_111 = 0xCF
: cc-emit-add-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]   1 cc-emit-byte
  [lit] 207 cc-emit-byte ;

\ SUB r/m64, r64 (0x29 /r): same encoding shape.
\   sub rdi, rcx -> 0xCF
: cc-emit-sub-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]  41 cc-emit-byte
  [lit] 207 cc-emit-byte ;

\ IMUL r64, r/m64 (0x0F AF /r): reg=dst, rm=src (NOTE the operand order is
\ flipped from add/sub).
\   imul rdi, rcx -> mod=11 reg=rdi=7 rm=rcx=1 -> 11_111_001 = 0xF9
: cc-emit-imul-rdi-rcx
  [lit]  72 cc-emit-byte
  [lit]  15 cc-emit-byte
  [lit] 175 cc-emit-byte
  [lit] 249 cc-emit-byte ;

\ Signed division: idiv divides rdx:rax by r/m64, leaving quotient in rax,
\ remainder in rdx.  We want rdi := rdi / rcx (or rdi % rcx).  Sequence:
\     mov rax, rdi      ; 48 89 F8
\     cqo               ; 48 99            (sign-extend rax into rdx)
\     idiv rcx          ; 48 F7 F9         (F7 /7, mod=11 rm=rcx=1 -> 11_111_001=0xF9)
\     mov rdi, rax|rdx  ; 48 89 C7 (rax) or 48 89 D7 (rdx)
: cc-emit-idiv-quotient
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 153 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 247 cc-emit-byte [lit] 249 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 199 cc-emit-byte ;

: cc-emit-idiv-remainder
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 153 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 247 cc-emit-byte [lit] 249 cc-emit-byte
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 215 cc-emit-byte ;

\ ===========================================================================
\ Function prologue / epilogue
\ ===========================================================================
\ Prologue:  push rbp ; mov rbp, rsp ; sub rsp, imm32
\ Epilogue:  mov rsp, rbp ; pop rbp ; ret

: cc-emit-prologue                                ( frame-bytes -- )
  [lit]  85 cc-emit-byte                          \ push rbp
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 229 cc-emit-byte                          \ mov rbp, rsp
  [lit]  72 cc-emit-byte
  [lit] 129 cc-emit-byte
  [lit] 236 cc-emit-byte                          \ sub rsp, imm32 prefix
  cc-emit-4le ;

: cc-emit-epilogue
  [lit]  72 cc-emit-byte
  [lit] 137 cc-emit-byte
  [lit] 236 cc-emit-byte                          \ mov rsp, rbp
  [lit]  93 cc-emit-byte                          \ pop rbp
  [lit] 195 cc-emit-byte ;                        \ ret

\ ===========================================================================
\ Comparisons: set rdi to 0 or 1 based on signed comparison of left/right.
\ ===========================================================================
\ The binary-op pattern (same as ALU) leaves rdi=left, rcx=right.  Each helper
\ emits 11 bytes:
\     xor rax, rax     48 31 C0
\     cmp rdi, rcx     48 39 CF      (sets flags from rdi - rcx = left - right)
\     setX al          0F 9X C0      (X = 4=E, 5=NE, C=L, D=GE, E=LE, F=G)
\     mov rdi, rax     48 89 C7
\
\ cc-emit-cmp-set ( setX-opcode -- )  Common tail; caller passes the second
\ byte of the setcc opcode (0x94, 0x95, 0x9C, 0x9D, 0x9E, 0x9F).
: cc-emit-cmp-set
  [lit]  72 cc-emit-byte [lit]  49 cc-emit-byte [lit] 192 cc-emit-byte   \ xor rax,rax
  [lit]  72 cc-emit-byte [lit]  57 cc-emit-byte [lit] 207 cc-emit-byte   \ cmp rdi,rcx
  [lit]  15 cc-emit-byte                                                  \ 0F prefix
  cc-emit-byte                                                            \ setX opcode
  [lit] 192 cc-emit-byte                                                  \ ModR/M for AL
  [lit]  72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 199 cc-emit-byte ; \ mov rdi,rax

: cc-emit-cmp-eq  [lit] 148 cc-emit-cmp-set ;     \ 0x94 setE
: cc-emit-cmp-ne  [lit] 149 cc-emit-cmp-set ;     \ 0x95 setNE
: cc-emit-cmp-lt  [lit] 156 cc-emit-cmp-set ;     \ 0x9C setL
: cc-emit-cmp-ge  [lit] 157 cc-emit-cmp-set ;     \ 0x9D setGE
: cc-emit-cmp-le  [lit] 158 cc-emit-cmp-set ;     \ 0x9E setLE
: cc-emit-cmp-gt  [lit] 159 cc-emit-cmp-set ;     \ 0x9F setG

\ ===========================================================================
\ Conditional / unconditional branches with rel32 fixups.
\ ===========================================================================

\ test rdi, rdi  -> 48 85 FF  (sets ZF=1 iff rdi == 0).
: cc-emit-test-rdi
  [lit]  72 cc-emit-byte
  [lit] 133 cc-emit-byte
  [lit] 255 cc-emit-byte ;

\ cc-emit-jz-rel32-placeholder ( -- patch-offset )
\ Emits `0F 84 00 00 00 00`; returns the file-offset of the rel32 cell
\ so the caller can later patch it with cc-patch-rel32-to-here.
: cc-emit-jz-rel32-placeholder
  [lit]  15 cc-emit-byte
  [lit] 132 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-4le ;

\ cc-emit-jmp-rel32-placeholder ( -- patch-offset )
\ Emits `E9 00 00 00 00`; returns the rel32 file-offset.
: cc-emit-jmp-rel32-placeholder
  [lit] 233 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-4le ;

\ cc-emit-call-rel32-placeholder ( -- patch-offset )
\ Emits `E8 00 00 00 00`; returns the rel32 file-offset.  Used for forward
\ function calls whose target vaddr is not yet known.  The caller threads the
\ patch offset onto a fixup list attached to the callee's prototype symbol;
\ the list is walked and patched when the function is later defined.
: cc-emit-call-rel32-placeholder
  [lit] 232 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-4le ;

\ cc-emit-jnz-rel32-placeholder ( -- patch-offset )
\ Emits `0F 85 00 00 00 00`; returns the rel32 file-offset.  Used by `||`'s
\ short-circuit fast-path: if LHS is non-zero, skip RHS and produce 1.
: cc-emit-jnz-rel32-placeholder
  [lit]  15 cc-emit-byte
  [lit] 133 cc-emit-byte
  cc-out-pos @
  [lit] 0 cc-emit-4le ;

\ cc-patch-rel32-to-here ( patch-offset -- )
\ rel32 = current cc-out-pos - (patch-offset + 4).
: cc-patch-rel32-to-here
  cc-out-pos @                                    ( patch-off target-off )
  over [lit] 4 + -                                ( patch-off rel32 )
  swap cc-out-patch-4le ;

\ NOTE: cc-emit-jmp-vaddr (which emits a backward unconditional jump to an
\ absolute vaddr — needed for `while`/`for` loops) lives in 110-cc-decl.fth
\ because it references cc-base-vaddr from 080-cc-elf.fth, which is loaded AFTER
\ 090-cc-emit.fth.

```

The file header announces the register convention.  Four registers
are reserved for compiled-code use: `rdi` (current expression
result), `rcx` (binary-op right operand), `rax` (`idiv` and SYS-V
return value), `rbp` (frame base).  Locals live at `[rbp - 8*(slot
+1)]`.  Everything else — `rsi`, `rdx`, `r8`–`r15` — is scratch
unless a specific encoder claims it.

This is a deliberately rigid choice.  A register allocator could
keep more values in registers, but the simplest expression
evaluator pushes intermediates to the *machine* stack and pops
them when needed.  That's why we have `push-rdi` / `pop-rdi`: the
parser's binary-op pattern is "evaluate left into `rdi`, push, eval
right into `rdi`, mov to `rcx`, pop original to `rdi`, apply op."

## 3. Stack ops and immediate loads

`cc-emit-mov-rdi-imm32` is the immediate-value loader: `48 C7 C7
<imm32>` = 7 bytes.  REX.W (`48`) is the 64-bit operand-size
prefix, `C7 /0` is "MOV r/m64, imm32" with ModR/M selecting `rdi`
as the destination.  The imm32 is sign-extended to 64 bits when
the CPU executes it, so this only works for values fitting in 32
signed bits — `cc-emit-movabs-rdi-imm64` (Ch 26) handles the
larger case.

The stack-op section is one byte per push, one byte per pop, for
every register we care about — plus REX.B-prefixed two-byte
variants for `r8`/`r9` (the extended registers added in x86-64).
Each encoder is one or two lines.

## 4. Local-variable addressing (a Ch 26 topic in primitive form)

The locals section here is the *encoder* for `[rbp - 8*(slot+1)]`
addressing; the *use* is for Ch 26.  `cc-disp8-from-slot` is the
arithmetic helper: slot 0 → -8 → 248, slot 1 → -16 → 240, slot 2
→ -24 → 232, and so on, all expressed as the 8-bit two's-
complement unsigned byte the `disp8` field of ModR/M wants.

The cap of 16 slots (the comment says `slots 0..15`) keeps the
displacement in signed-byte range (-128..-8).  Past that we'd need
`disp32` and a four-byte displacement instead of one — doable but
not needed for M2-Planet's functions.

`cc-emit-load-local`, `cc-emit-store-local`, `cc-emit-lea-rdi-
local`, `cc-emit-load-via-rdi`, `cc-emit-load-byte-via-rdi`,
`cc-emit-store-via-rcx`, `cc-emit-store-byte-via-rcx` are four-byte
encoders apiece (`48 8B/89/8D 7D/3F/39 <disp8>` for the locals,
three-byte variants for dereference patterns).  The encoding
arithmetic is in the comments — read one and you can predict the
rest.

`cc-emit-shl-rdi-imm8` and `cc-emit-add-rdi-imm32` are pointer-
arithmetic primitives: shift left for array indexing (multiply by
`sizeof(T)`), add immediate for struct field-offset bias.

The param-spill helpers (`cc-emit-store-local-from-rsi` and
friends) are five tiny variants of `mov [rbp+disp8], <regsrc>` for
the SYS-V argument registers.  They live alongside the locals
because they target the same `[rbp+disp8]` locations; Ch 26 uses
them at function prologue time.

`cc-emit-load-local-into-rax` is the indirect-call dual: load a
function-pointer local into `rax` so the SYS-V argument registers
(which are already loaded with the call's args in `rdi`/`rsi`/
etc.) survive intact.  `cc-emit-call-rax` then dispatches.

## 5. Register-to-register moves, ALU, and prologue/epilogue

Four register-to-register moves — `mov rcx, rdi`, `mov rax, rdi`,
`mov rdi, rax`, `mov rbx, rdi` — alongside `cmp rbx, imm32` and
`xor rax, rax`.  Each move is 3 bytes (`48 89 <ModR/M>`); `cmp
rbx, imm32` is `48 81 <ModR/M> <imm32>`.  The `xor rax, rax` is the
standard 3-byte register-zeroing idiom — shorter than `mov rax, 0`
would be.

The ALU section codes the four basic arithmetic operators: `add`,
`sub`, `imul`, plus signed `idiv` in two flavours (`cc-emit-idiv-
quotient` for `/`, `cc-emit-idiv-remainder` for `%`).  `idiv` is
the long one — eleven bytes, because it requires `mov rax, rdi`
to put the dividend in the right register, `cqo` to sign-extend
`rax` into `rdx:rax`, `idiv rcx` for the actual division, then
either `mov rdi, rax` (quotient) or `mov rdi, rdx` (remainder).

`cc-emit-prologue` and `cc-emit-epilogue` are the standard SYS-V
AMD64 frame builders.  Prologue: `push rbp ; mov rbp, rsp ; sub
rsp, <frame-bytes>` — 1 + 3 + 7 = 11 bytes, where the `sub` carries
a 4-byte immediate `<frame-bytes>` behind a 3-byte opcode prefix.
Epilogue: `mov rsp, rbp ; pop rbp ; ret` — 5 bytes.  The prologue
takes a frame-size argument because the parser knows the local
count by the time it emits it (Chs 30–31 cover the parser; the
prologue is "emit me 11 bytes, with this 32-bit frame size baked
in").

## 6. Comparisons and conditional set

`cc-emit-cmp-set` is the shared tail for all six comparisons.  It
emits 11 bytes:

```
xor rax, rax     48 31 C0      ; clear rax
cmp rdi, rcx     48 39 CF      ; set flags from left - right
setX al          0F 9X C0      ; set al = 1 iff condition holds
mov rdi, rax     48 89 C7      ; rdi := rax (now 0 or 1)
```

The six `cc-emit-cmp-*` words differ only in the second byte of
the `setX` opcode: `0x94` (setE), `0x95` (setNE), `0x9C` (setL),
`0x9D` (setGE), `0x9E` (setLE), `0x9F` (setG).  The signed
variants (`setL`/`setGE`/`setLE`/`setG`) are what C's `<`, `>=`,
`<=`, `>` produce — matching C's signed-integer semantics for the
`int` type.

The output is a clean 0/1 boolean — *not* the seed Forth's `-1/0`
convention.  Ch 27's `&&` / `||` short-circuit codegen assumes
this 0/1 invariant.

## 7. Branches and `rel32` placeholders

The branch encoders are the codegen equivalent of Forth's `if,`
(Ch 11): emit a conditional jump with a placeholder displacement,
remember where the placeholder went, fill in the right value when
the target is known.

`cc-emit-jz-rel32-placeholder` emits `0F 84 00 00 00 00`, returns
the offset of the four-byte rel32.  `cc-emit-jnz-rel32-placeholder`
is the same with opcode `0F 85`.  `cc-emit-jmp-rel32-placeholder`
emits `E9 00 00 00 00`.  `cc-emit-call-rel32-placeholder` emits
`E8 00 00 00 00`.

`cc-patch-rel32-to-here` is the patch: read `cc-out-pos`, compute
`target - (patch-off + 4)` (the displacement is from the byte
after the rel32), and `cc-out-patch-4le` writes it.

The NOTE at the bottom of this region is worth reading: a `jmp` to
an *absolute* vaddr (for backward branches in `while`/`for`) needs
`cc-base-vaddr` from `080-cc-elf.fth`, which is loaded *after*
`090-cc-emit.fth`.  That's why `cc-emit-jmp-vaddr` lives in
`110-cc-decl.fth` instead of here — load order matters.

## 8. The shape of the rest

What this chapter has covered is the bottom layer: pure
instruction encoders.  Ch 26 picks up at line 412 with:
- `movabs rdi, imm64` and its placeholder variant for forward-
  declared function loads;
- `cc-add-fixup-to-list` (the linked-list of patch offsets that
  Ch 31 walks when a forward-declared function gets defined);
- `cc-emit-string-bytes` (the string-literal escape decoder);
- the eleven libc shims (`putchar` through `free`);
- bitwise / shift / `inc-mem` / `dec-mem` / unary `!`;
- global-data emission and global-vaddr fixups.

Everything in Ch 26 calls into encoders defined in this chapter.

## Try it

```sh
./build.sh
tests/cc/stage-a-check.sh   # builds M2-Planet via cc-out and compares
                            # the .M1 output to the GCC-built reference
```

If `stage-a-check.sh` passes, the codegen is producing byte-correct
machine code at scale.

To inspect individual encoders, drive the compiler from stdin with
a one-shot Forth word that emits a few encoded instructions to a
NUL-terminated path and writes the result.  We use the pre-baked
`cc-out-path` from `120-cc-main.fth` instead of `s"`, since `s"` is
not NUL-terminated and `cc-write-output` requires NUL termination:

```sh
./build.sh
{
  for f in 010-lib.fth 020-cc-arena.fth 030-cc-io.fth \
           040-cc-prep.fth 050-cc-lex.fth \
           060-cc-types.fth 070-cc-sym.fth \
           080-cc-elf.fth 090-cc-emit.fth; do
    sed -e 's/\\.*$//' -e 's/([^)]*)//g' "$f"
  done
  cat <<'FORTH'
    \ NUL-terminated path "/tmp/cc-out\0" in the dictionary
    create probe-path
    [lit]  47 c, [lit] 116 c, [lit] 109 c, [lit] 112 c,
    [lit]  47 c, [lit]  99 c, [lit]  99 c, [lit]  45 c,
    [lit] 111 c, [lit] 117 c, [lit] 116 c, [lit]   0 c,

    : probe
      cc-out-init  cc-emit-elf-header
      [lit] 42 cc-emit-mov-rdi-imm32
      cc-emit-push-rdi
      cc-emit-add-rdi-rcx
      probe-path cc-write-output
      bye ;
    probe
FORTH
} | grep -v '^[[:space:]]*$' | ./seed-forth

objdump -D -b binary -m i386:x86-64 -M intel /tmp/cc-out | tail -10
EOF
```

You should see `mov rdi, 0x2a ; push rdi ; add rdi, rcx` in the
disassembly after the 120-byte ELF preamble.

## Exercises

1. **★** Read `cc-emit-elf-header`.  Why does it emit zeros for
   `p_filesz`?  What's the alternative (and what would it cost)?

2. **★★** The single R-W-X segment is unusual.  Real-world ELFs separate
   `.text` (R-X) from `.data` (R-W) for memory safety.  What
   would adding a second program header cost in bytes and in
   complexity?

3. **★★** Tabulate every instruction encoder by name and bytes-emitted.
   Roughly how many distinct x86-64 instructions does this
   codegen know?

4. **★★★** Add an `imul rax, rbx, imm32` encoder.  Where would it be
   useful?  (Hint: scalar multiplication by a constant could
   replace `mov rcx, imm ; imul rdi, rcx` for known constants.)

5. **★★★** The `cmp-set` helpers emit 11 bytes; a tighter encoding would
   use `setX r/m8` directly into `dil` and `movzx rdi, dil`.
   Estimate the saving and decide whether it's worth the code
   change.

## Takeaways

- The output ELF is a single R-W-X PT_LOAD at `0x400000` with
  one back-patched field (`p_filesz`).  The simplicity is the
  point — no section headers, no relocations, no separate data
  segment.
- Each x86-64 instruction the compiler emits has its own Forth
  word.  This is the alternative to a generic "assemble these
  tokens" pass: opcode bytes live in the source, not in a table.
- `rel32` placeholders + `cc-patch-rel32-to-here` are the codegen
  equivalent of Forth's `if,` fixup-on-the-stack.  The same
  mechanism handles `if`, `while`, `for`, `||`, `&&`, and
  forward function calls (Chs 27, 30, 31).

Next: Chapter 26 — Codegen, Part 2: Calls, Locals, Shims, Globals.
