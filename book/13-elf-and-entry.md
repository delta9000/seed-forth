# Chapter 13 — The ELF and the Entry Point

```text
Missing capability: the 2,040 bytes of hex have to be made executable somehow.
New pattern: a minimal ELF64 header plus one PT_LOAD with R|W|X over the whole 16 MiB segment.
Artifact after this chapter: the boot prologue — ELF header, _start, sysvar init, jump to REPL.
Proof link: the C compiler's own ELF emission (Ch 25) reuses the same shape and the same addresses.
```

This chapter reads the first 63 lines of `000-seed.hex0`: a
64-byte `Elf64_Ehdr`, a single `Elf64_Phdr` describing one
`PT_LOAD` segment with `R|W|X` flags, the `_start` prologue, the
six-instruction sysvar init at `0x085`, and the `JMP repl` at
`0x0CD` that hands control to the interpreter.  Open
`000-seed.hex0` to lines 1–63 and have an ELF reference (`readelf
-a` output, or just the Wikipedia "Executable and Linkable
Format" page) at hand.

By the end you'll be able to read a minimal 64-bit Linux ELF
executable header field by field, compute the entry-point address
`0x400078` and check it against the byte at file offset `0x18`,
trace the `_start` prologue and the sysvar-init code at `0x085`, and
explain why the program header maps 16 MiB even though the on-disk
image is only 2,040 bytes (so the Forth compiler can scratch into
pages that don't exist on disk).  Each primitive's body bytes are
deferred to Chs 14–19; dictionary headers (the
`--- bye @ 0x44D ---` style entries that tie names to those bodies)
are Ch 17; `parse_decimal_code` and the REPL are Ch 20.

---

```
       __
   __( o)>   "twelve chapters of black boxes.  the boxes have
   \___/      hex inside.  hope you brought a hex chart."
```

The seed is one file: `000-seed.hex0`, 752 lines of hand-assembled
hex.  The Stage-0 toolchain (`hex0-seed` from the Guix Full Source
Bootstrap) consumes those lines, ignores the comments after `;`, and
writes the resulting bytes to disk verbatim.  Output: a 2,040-byte
ELF executable that *is* `seed-forth`.  No primitive bodies in
this chapter — those start in Ch 14.

## 1. Why we start at the top

Every primitive in the next seven chapters is found by its address.
`dup_code` lives at `0x40013B`.  `nand_code` at `0x4001AA`.
`lit_code` at `0x400419`.  The dictionary headers near the bottom of
the file each contain a relative jump back to a primitive body — and
those relative jumps are written by hand, computed in advance, and
not patched at load time.

This works because the *whole file is loaded contiguously at
`0x400000`*, with the bytes at file offset `N` ending up at virtual
address `0x400000 + N`.  That is what the ELF header and the program
header arrange.  Read them first and every later "rel32 = …"
arithmetic in this codebase will make sense.

## 2. The ELF magic and `Elf64_Ehdr`

The first 64 bytes of any ELF file are an `Elf64_Ehdr`.  Cross-
reference `man 5 elf` if you want a field-by-field formalism; here is
the seed's copy, four bytes at a time.

```
7F 45 4C 46    ; e_ident[0..3] = magic "\x7fELF"
02             ; e_ident[EI_CLASS]   = ELFCLASS64
01             ; e_ident[EI_DATA]    = ELFDATA2LSB   (little-endian)
01             ; e_ident[EI_VERSION] = EV_CURRENT
00             ; e_ident[EI_OSABI]   = ELFOSABI_NONE (System V)
00             ; e_ident[EI_ABIVERSION]
00 00 00 00 00 00 00 ; e_ident padding (zeros)
02 00          ; e_type    = ET_EXEC
3E 00          ; e_machine = EM_X86_64
01 00 00 00    ; e_version = 1
78 00 40 00 00 00 00 00 ; e_entry  = 0x400078
40 00 00 00 00 00 00 00 ; e_phoff  = 64
00 00 00 00 00 00 00 00 ; e_shoff  = 0  (no section headers)
00 00 00 00    ; e_flags
40 00          ; e_ehsize    = 64
38 00          ; e_phentsize = 56
01 00          ; e_phnum     = 1
00 00          ; e_shentsize = 0
00 00          ; e_shnum     = 0
00 00          ; e_shstrndx  = 0
```

Three numbers in there are doing heavy work.

**`e_entry = 0x400078`** is the address the kernel jumps to after
loading the image.  We will compute this address from the file
structure in §4.

**`e_phoff = 64`** says "the program-header table starts at file
offset 64."  Since the ELF header is itself 64 bytes, the program
header sits immediately after — no padding, no slack.

**`e_shoff = 0`** says "no section headers."  Sections are a
*linking* concept; an executable file does not need them.  Skipping
the section-header table saves bytes and removes a source of
complexity.  `readelf -h` will report the section count as zero.

Everything else is a constant the kernel checks before accepting the
file: it must be 64-bit (`02`), little-endian (`01`), an executable
(`02 00`), targeted at x86-64 (`3E 00`).

## 3. The single `Elf64_Phdr`

Bytes 64–119 are the one program header.  `PT_LOAD` with `R|W|X`
flags, mapping file offset `0` for 2,040 bytes to virtual address
`0x400000` for 16 MiB.

```
01 00 00 00              ; p_type   = PT_LOAD
07 00 00 00              ; p_flags  = R|W|X
00 00 00 00 00 00 00 00  ; p_offset = 0
00 00 40 00 00 00 00 00  ; p_vaddr  = 0x400000
00 00 40 00 00 00 00 00  ; p_paddr  = 0x400000  (ignored on Linux)
F8 07 00 00 00 00 00 00  ; p_filesz = 2040
00 00 00 01 00 00 00 00  ; p_memsz  = 0x1000000 (16 MiB)
00 10 00 00 00 00 00 00  ; p_align  = 0x1000
```

The two `p_*sz` fields tell the kernel a story: "on disk there are
`p_filesz` bytes (2,040); in memory please make `p_memsz`
(16 MiB) of virtual space available, zero-filling anything past the
end of the file."  That is how `seed-forth` writes into `HERE` at
`0x401000` (just above the file image) without ever calling `mmap`.
The whole compile-time heap, the data stack at `0x411000`, the I/O
scratch byte at `0x412000`, the token buffer at `0x412800`, and the
sysvar page at `0x413000` are all *inside* this single mapping.

R|W|X is unusual for modern executables — most loaders separate code
(`R-X`) and data (`R-W`).  The seed has one segment because it
*writes new machine code into the same region it executes from*: the
REPL's compile-mode handler emits `CALL` instructions at `HERE`, and
those bytes have to be executable the moment they are written.  Two
segments would force an `mprotect` syscall every time `HERE` crossed
a page boundary, which is the kind of indirection a 2,040-byte
binary cannot afford.

`p_align = 0x1000` is the system page size.  Both `p_offset` and
`p_vaddr` are multiples of `0x1000`, which keeps the kernel happy.

## 4. `_start` at `0x400078`

Why is the entry point `0x400078`?

The file image starts at virtual address `0x400000` (from `p_vaddr`).
The ELF header is 64 bytes (`0x40`).  The program header is 56 bytes
(`0x38`).  Total: 120 bytes (`0x78`).  So the first byte after the
two headers lives at `0x400000 + 0x78 = 0x400078`.

That is `_start`:

```
48 BD 00 10 41 00 00 00 00 00   ; mov rbp, 0x411000
48 31 FF                        ; xor rdi, rdi
```

Two instructions, thirteen bytes.

`mov rbp, 0x411000` initialises the **data stack**.  Throughout the
seed, `rbp` is the data-stack pointer (it grows *down* — `sub rbp, 8`
to push a slot, `add rbp, 8` to pop one).  The base `0x411000` is
17 pages above `0x400000`; the stack will grow down toward the
sysvars and the heap.

`xor rdi, rdi` clears the **TOS register cache**.  `rdi` holds the
top of the data stack as a register, not in memory; every primitive
in Ch 14 works on `rdi` directly and spills to `[rbp]` only when
forced.  Starting `rdi` at zero is harmless: the first real push will
spill this zero and overwrite the register with the new value.

## 5. The sysvar init at `0x085`

Right after `_start`, six `mov [imm32], imm32` instructions seed the
sysvar page at `0x413000`.  Each is 12 bytes long, total 72 bytes.

```
48 C7 04 25 00 30 41 00 00 00 00 00   ; [STATE]       = 0
48 C7 04 25 08 30 41 00 E8 07 40 00   ; [LATEST]      = 0x4007E8
48 C7 04 25 10 30 41 00 00 10 40 00   ; [HERE]        = 0x401000
48 C7 04 25 18 30 41 00 00 00 00 00   ; [LAST_FOUND]  = 0
48 C7 04 25 20 30 41 00 00 00 00 00   ; [NUMBER_HOOK] = 0
48 C7 04 25 28 30 41 00 00 00 00 00   ; [INPUT_FD]    = 0
```

`STATE = 0` boots us in interpret mode.  `HERE = 0x401000` puts the
next-byte-to-write pointer at the page right above the ELF image, so
the first `:` definition starts a clean page.  `LAST_FOUND`,
`NUMBER_HOOK`, and `INPUT_FD` start at zero; the first two are
filled by `find_code` and by Forth-level extensions, the third
selects stdin.

The interesting one is `LATEST = 0x4007E8`.  That is the address of
the dictionary entry for `'` — the very last word defined in the
seed image.  The dictionary is a linked list of headers, each
pointing back to the previous one (Ch 17 has the picture); the head
of the list is whoever was defined last.  Rather than walk the chain
at runtime to find that tail, the seed *initialises `LATEST` to its
known assembly-time value*.  `0x4007E8` is the address of the `'`
entry's link cell, and the hex0 file just hard-codes it here.

This is a small but characteristic move: anything that can be
resolved at assembly time is resolved at assembly time, not runtime.
The cost is that adding a new primitive means recomputing this
constant by hand; the benefit is that startup is six `mov`s and
nothing else.

## 6. `JMP repl` at `0x0CD`

After the sysvar init, the entry-code section ends with one
unconditional jump.

```
;; ----- @ 0x0CD: jmp repl (rel32 = 0x35E - 0x0D2 = 0x0000028C) -----
E9 8C 02 00 00
```

`E9` is the opcode for "`JMP` with a 32-bit signed displacement
relative to the *next* instruction."  The next instruction starts at
`0x0CD + 5 = 0x0D2`.  The REPL lives at file offset `0x35E` (virtual
address `0x40035E`).  The displacement is `0x35E - 0x0D2 = 0x28C`,
encoded little-endian as `8C 02 00 00`.

You will see this arithmetic — `target − (call_site + size)` — over
and over for the rest of Part II.  Every `CALL` and `JMP` in the
seed uses a 32-bit signed displacement; every dictionary entry ends
in a `JMP rel32` back to its body.  All of those `rel32`s were
computed by hand and pasted in.

That is the seed's whole boot sequence: identify yourself as an ELF;
ask for one 16 MiB segment; initialise two registers and six
sysvars; jump to the REPL.  90 bytes from `_start` to the jump, of
which 72 are sysvar initialisation.  Everything else in the file is
either a primitive body or a dictionary header — and from here on
the chapters are organised by topic, not by offset.

## Canonical source

`000-seed.hex0` is hand-assembled and its byte-order is load-bearing
(every `rel32` was computed against it), so we declare the whole
file as one root block here, with every chunk reference in source
order.  Subsequent chapters (Chs 14–20) define the bodies of the
chunks they introduce; the awk tangler stitches them in at the
positions named below.  Each chunk body ends with the blank line
that separates it from the next section, so concatenation yields
byte-identical source.

```hex0 file=000-seed.hex0
<<file-header-comment>>
<<elf-header>>
<<program-header>>
<<entry-point>>
<<sysvar-init>>
<<jmp-to-repl>>
<<bye-code>>
<<emit-code>>
<<key-code>>
<<dup-code>>
<<drop-code>>
<<swap-code>>
<<to-r-code>>
<<r-from-code>>
<<fetch-code>>
<<store-code>>
<<cfetch-code>>
<<cstore-code>>
<<plus-code>>
<<nand-code>>
<<zeq-code>>
<<find-code>>
<<here-code>>
<<comma-code>>
<<execute-code>>
<<read-word>>
<<colon-code>>
<<semicolon-code>>
<<repl>>
<<lit-code>>
<<branch-code>>
<<zbranch-code>>
<<dictionary-entries>>
<<parse-decimal-code>>
<<bracket-lit-code>>
<<bracket-lit-dict>>
<<syscall6-code>>
<<syscall6-dict>>
<<divide-code>>
<<divide-dict>>
<<r-at-code>>
<<star-code>>
<<state-code>>
<<latest-code>>
<<tick-code>>
<<late-dicts>>
```

This chapter defines the first six chunks below.

```hex0 chunk=file-header-comment
;; 000-seed.hex0 — x86-64 Linux Forth Seed
;;
;; This file is a synthesis artifact of AI-collaborative research.
;; Co-authored by an ensemble of LLMs (Claude, Gemini, Codex, DeepSeek,
;; Qwen, Kimi, Gemma, MiniMax) under human architectural direction.
;;
;; License: MIT (see /LICENSE)
;;
```

```hex0 chunk=elf-header
;; ===== ELF64 header (64 bytes) =====
;; Layout reference: man 5 elf, Elf64_Ehdr
7F 45 4C 46                               ; e_ident[0..3] = magic "\x7fELF"
02
01
01
00
00
00 00 00 00 00 00 00
02 00                                     ; e_type = ET_EXEC
3E 00                                     ; e_machine = EM_X86_64
01 00 00 00                               ; e_version = 1
78 00 40 00 00 00 00 00                   ; e_entry = 0x400078
40 00 00 00 00 00 00 00                   ; e_phoff = 64
00 00 00 00 00 00 00 00                   ; e_shoff = 0
00 00 00 00                               ; e_flags
40 00                                     ; e_ehsize = 64
38 00                                     ; e_phentsize = 56
01 00                                     ; e_phnum = 1
00 00
00 00
00 00

```

```hex0 chunk=program-header
;; ===== Program header (56 bytes), one PT_LOAD =====
01 00 00 00                               ; p_type = PT_LOAD
07 00 00 00                               ; p_flags = R|W|X
00 00 00 00 00 00 00 00                   ; p_offset = 0
00 00 40 00 00 00 00 00                   ; p_vaddr = 0x400000
00 00 40 00 00 00 00 00                   ; p_paddr = 0x400000
F8 07 00 00 00 00 00 00                   ; p_filesz = 2040
00 00 00 01 00 00 00 00                   ; p_memsz  = 0x1000000 (16 MiB) for compiler buffers
00 10 00 00 00 00 00 00                   ; p_align = 0x1000

```

```hex0 chunk=entry-point
;; ===== Code at 0x400078 =====
;;   rbp = data-stack pointer (grows down)
;;   rdi = TOS register
;;   0x412000 = single-byte I/O scratch (emit/key)
;;   0x412800 = token buffer (read_word)
;;   0x411000 = data-stack top
;;   0x413000 sysvar page: STATE/LATEST/HERE/LAST_FOUND/NUMBER_HOOK/INPUT_FD
;;
;; @ 0x078: _start
48 BD 00 10 41 00 00 00 00 00             ; mov rbp, 0x411000
48 31 FF                                  ; xor rdi, rdi

```

```hex0 chunk=sysvar-init
;; ----- sysvar init @ 0x085 -----
48 C7 04 25 00 30 41 00 00 00 00 00       ; mov [STATE], 0
48 C7 04 25 08 30 41 00 E8 07 40 00       ; mov [LATEST], 0x4007E8  ("'" entry)
48 C7 04 25 10 30 41 00 00 10 40 00       ; mov [HERE], 0x401000
48 C7 04 25 18 30 41 00 00 00 00 00       ; mov [LAST_FOUND], 0
48 C7 04 25 20 30 41 00 00 00 00 00       ; mov [NUMBER_HOOK], 0
48 C7 04 25 28 30 41 00 00 00 00 00       ; mov [INPUT_FD], 0

```

```hex0 chunk=jmp-to-repl
;; ----- @ 0x0CD: jmp repl (rel32 = 0x35E - 0x0D2 = 0x0000028C) -----
E9 8C 02 00 00

```

## Try it

```sh
./build.sh                    # assembles 000-seed.hex0; you get a 2040-byte ELF.
wc -c ./seed-forth            # should print 2040
file ./seed-forth             # ELF 64-bit LSB executable, x86-64
readelf -h ./seed-forth       # confirms the header we just read
readelf -l ./seed-forth       # confirms the one PT_LOAD segment
```

Compare the `readelf -h` output to the hex you read in §2 field by
field.  `e_entry` should be `0x400078`; `e_phoff` should be `64`;
`e_phnum` should be `1`.

## Exercises

1. **★★ Trace.** The entry point is at `0x400078`.  The header is 64 bytes plus one
   56-byte program header — total 120 bytes.  Why is the entry at
   offset `0x78` (=120) and not, say, `0x100`?  What would change if
   the seed reserved padding for future program-header entries?

2. **★★ Trace.** `p_memsz = 16 MiB` but `p_filesz = 2040`.  What does the kernel do
   with the bytes between `2040` and `16 MiB`?  Trace what happens
   when seed-forth writes the first byte at `0x420000`: does the page
   exist before the write?  After?

3. **★★ Trace.** The sysvar `LATEST` is initialised at assembly time to the entry
   of the `'` primitive (`0x4007E8`).  Why not initialise it to zero
   and have the REPL walk the chain to find the tail?  (Hint: count
   the syscalls and instructions involved in each option.)

4. **★★★ Extend.** Why R|W|X for the single segment?  Sketch the changes needed to
   split it into R-X (code) + R-W (heap + sysvars + stack).  Where
   would `mprotect` calls have to go?  How many bytes does each one
   cost?

## Takeaways

- A 64-bit Linux ELF can be written by hand in 120 bytes (one
  `Elf64_Ehdr` + one `Elf64_Phdr`) and still satisfy the kernel.
- The seed maps one big R|W|X segment that includes its own
  compile-time-allocated buffers, avoiding any need for `mmap` or
  `mprotect` during normal operation.
- Every primitive in the next seven chapters is reachable from
  `_start` by direct address; the seed resolves at assembly time
  anything that can be resolved at assembly time.

Next: Chapter 14 — Stack Primitives in Machine Code.
