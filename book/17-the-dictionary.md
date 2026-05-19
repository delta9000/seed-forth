# Chapter 17 — The Dictionary

## Goal

By the end of this chapter the reader can:

- explain the dictionary entry layout `link(8) flags(1) nlen(1)
  name(N) body(M)` and walk the linked list backwards from `LATEST`;
- read `find_code` and explain its two-level loop (chain walk +
  byte comparison) and the `LAST_FOUND` side effect;
- read `here_code`, `comma_code`, `execute_code`, `tick_code`,
  `state_code`, `latest_code`, and `read_word`, and explain what
  each contributes to the parse-then-resolve cycle.

## Source coverage

`000-seed.hex0` lines 171–262 (`find_code`, `here_code`,
`comma_code`, `execute_code`, `read_word`), lines 387–554
(all dictionary entries from `bye` through `0branch`), and
lines 684–752 (`state_code`, `latest_code`, `tick_code` plus
their dictionary entries and the trailing `r@`, `*`, `state`,
`latest`, `'` entries).

## Concepts introduced

- **The dictionary as a linked list of headers.**  Each entry stores
  a pointer to the previous entry's link cell.  `LATEST` is the
  head; walking link→link backwards ends at the null pointer in the
  very first entry (`bye`).
- **`find_code` ( c-addr u -- xt-or-0 ).**  Walks the chain;
  compares each entry's name length and bytes to the given token;
  returns the body address on success or `0` on miss; updates
  `LAST_FOUND` as a side effect so the caller can read the flags
  byte.
- **`here_code` and `comma_code`.**  The two cell-level memory
  primitives the compiler leans on.
- **`execute_code` ( xt -- ).**  Pops an xt and jumps to it via
  `jmp rax` — a tail call, no return frame.
- **`tick_code` ( -- xt ).**  Read the next token and look it up;
  returns the xt or `0`.  The "name → address" half of metacompiler
  reflection.
- **`state_code` and `latest_code`.**  Sysvar accessors that push
  the *address* of a sysvar cell, so the caller can `@` or `!` it
  with the ordinary memory primitives.
- **`read_word` ( -- ; rax = token-len ).**  Byte-by-byte token
  assembly: skip leading whitespace, copy non-whitespace into the
  token buffer at `0x412800`, stop on whitespace or EOF.

## Concepts carried in

- The sysvar layout from Ch 13 (`STATE`, `LATEST`, `HERE`,
  `LAST_FOUND`).
- The data-stack convention from Ch 14.
- `bytes-eq`-style comparison from Ch 12 — but here implemented
  inline in machine code, not in Forth.
- The token-buffer page convention from Ch 13.

## Concepts deferred

- The REPL's use of `find_code` and `execute_code` — Ch 20.
- The `[lit]` IMMEDIATE entry — Ch 18 §5 (the `<<bracket-lit-dict>>`
  header that flips the IMMEDIATE bit).

---

The dictionary is the seed's only data structure.  There is no hash
table, no symbol table, no environment frame.  Just a linked list
of headers walked by `find_code`, each header pointing back to the
previous one.  Everything the REPL knows about — every primitive,
every Forth-level definition added by `:` — lives in this list.

The list is grown forward (new entries appended at `HERE`) but
searched backward (from `LATEST`).  That makes the most recent
definition the *first* one a lookup finds, which is exactly what
you want for shadowing: redefining `dup` later in the source pushes
a new entry whose name matches the lookup first, and the original
becomes invisible.

**How this chapter is organized.**  The chapter has three logical
units packed together.  *Dictionary core* (§§1–4) is the header
layout, lookup, and the two primitives that build entries (`here`,
`,`) plus the one that runs them (`execute`).  *The token reader
and sysvar accessors* (§§5–7) covers `read_word`, `state`,
`latest`, and `tick` — the support layer that lets the REPL feed
the dictionary at parse time.  *The actual dictionary entries*
(§§8–9) lists the entries the seed bakes in: the 32 primitives'
headers and the few late entries that depend on `read_word`.  If
you only want the lookup algorithm, §§1–2 are self-contained; if
you only want how the REPL connects to the dictionary, skip to §5.

## 1. The header layout

Each dictionary entry is:

```
offset  size  field
   0     8    link        — address of previous entry's link cell, or 0
   8     1    flags       — bit 0 = IMMEDIATE
   9     1    nlen        — name length in bytes
  10     N    name        — N bytes of the word's name (ASCII)
 10+N    M    body        — machine code for the word
```

After hex-assembly, the seed contains 24 hand-laid-out headers in a
single block running from `0x44D` (`bye`) to `0x5F8` (`0branch`),
followed by the later additions at the end of the file.

Each header's `link` points at the *previous header's link cell*.
The very first header (`bye`) has `link = 0`.  At runtime, the
sysvar `LATEST` points at the most recent entry's link cell.

A picture for the first three entries:

```
  bye_entry @ 0x44D:
    link  = 0x00000000      ← end of chain
    flags = 00
    nlen  = 03
    name  = "bye"
    body  = jmp bye_code

  emit_entry @ 0x45F:
    link  = 0x0040044D      ← points at bye_entry's link
    flags = 00
    nlen  = 04
    name  = "emit"
    body  = jmp emit_code

  key_entry @ 0x472:
    link  = 0x0040045F      ← points at emit_entry's link
    flags = 00
    nlen  = 03
    name  = "key"
    body  = jmp key_code

  ...
  ' (tick) @ 0x7E8 ← LATEST initialised here
```

`find` walks this chain backwards from `LATEST`.  Each step is one
`@` to load the link cell.

The `body` for every hand-laid header is a 5-byte `JMP rel32` to
the primitive's code.  That is why the headers and the bodies can
sit far apart in the file: the JMP makes the layout topology-free.

## 2. `find_code` ( c-addr u -- xt-or-0 )

The largest primitive in the seed: 86 bytes of machine code, twice
the size of anything else in `000-seed.hex0`.

```hex0 chunk=find-code
;; ----- find_code @ 0x1C5 -----
48 8B 75 00
48 83 C5 08
48 8B 0C 25 08 30 41 00
48 85 C9
74 3D
48 0F B6 41 09
48 39 F8
75 2E
48 89 FA
4C 8D 41 0A
49 89 F1
48 85 D2
74 13
41 8A 00
41 3A 01
75 17
49 FF C0
49 FF C1
48 FF CA
EB E8
48 89 0C 25 18 30 41 00
4C 89 C7
C3
48 8B 09
EB BE
48 31 FF
C3

```

Read it as two nested loops:

```
;; entry: rdi = name length u, [rbp] = c-addr
mov rsi, [rbp]        ; rsi = c-addr (the token bytes)
add rbp, 8            ; pop c-addr's slot
mov rcx, [LATEST]     ; rcx = head of chain

.next:                ; outer loop: walk the link chain
  test rcx, rcx
  jz .miss            ; end of chain — fail
  movzx rax, byte [rcx+9]   ; rax = nlen
  cmp rax, rdi
  jne .skip                  ; length mismatch — try next entry
  ;; lengths match; compare names byte by byte
  mov rdx, rdi              ; rdx = remaining count
  lea r8,  [rcx+10]         ; r8  = entry's name bytes
  mov r9,  rsi              ; r9  = caller's name bytes
.bcmp:
  test rdx, rdx
  jz .hit                    ; all bytes matched — found it
  mov r10b, [r8]
  cmp r10b, [r9]
  jne .skip                  ; byte mismatch — try next entry
  inc r8
  inc r9
  dec rdx
  jmp .bcmp
.skip:
  ;; advance to previous entry
  ; (the seed reuses the slot: load *[rcx] into rcx and re-loop)
  mov rcx, [rcx]
  jmp .next
.hit:
  mov [LAST_FOUND], rcx     ; record entry address for caller
  mov rdi, r8               ; r8 currently points at end of name = start of body
  ret
.miss:
  xor rdi, rdi              ; return 0
  ret
```

The hex preserves all of the above — outer loop, byte-compare inner
loop, hit path, and miss path — in 86 bytes.  Three details are worth
pointing out.

**`LAST_FOUND` is a side channel.**  On a hit, `find_code` stores
the address of the matched entry's link cell into the sysvar at
`0x413018`.  The REPL (Ch 20) reads this in compile mode to check
the IMMEDIATE bit before deciding whether to call-now or emit-a-
call-instruction.  Returning just the xt isn't enough; the *flag
byte* sits one cell past the link, and the caller needs both.

**The body address is `[rcx+10+nlen]`.**  Right at the moment of
hit, `r8` has been advancing through the name bytes (one byte per
loop iteration), so when `rdx` hits zero `r8` is sitting at the
first byte *after* the name — which is the start of the body.  No
extra arithmetic.  The seed picks this register dance precisely
because it ends up with the answer in `r8` for free.

**The miss path is a tail.**  `.miss` lives *outside* the main
loop body, at lines 197–198, because the conditional jumps in the
loop are limited to 8-bit `rel8` offsets.  Putting `.miss` and the
single-byte tail at the end keeps every branch within reach.

## 3. `here_code` and `comma_code`

`here_code` returns the *contents* of the HERE sysvar — the
next-byte-to-write address.

```hex0 chunk=here-code
;; ----- here_code @ 0x21B -----
48 83 ED 08
48 89 7D 00
48 8B 3C 25 10 30 41 00
C3

```

```
sub rbp, 8
mov [rbp], rdi
mov rdi, [HERE]    ; HERE sysvar lives at 0x413010
ret
```

A standard push (spill the old TOS, load the new) where the new TOS
is the contents of `[0x413010]`.

`comma_code` writes 8 bytes at HERE and advances HERE by 8.

```hex0 chunk=comma-code
;; ----- comma_code @ 0x22C -----
48 8B 04 25 10 30 41 00
48 89 38
48 83 C0 08
48 89 04 25 10 30 41 00
48 8B 7D 00
48 83 C5 08
C3

```

```
mov rax, [HERE]        ; rax = next-byte-to-write
mov [rax], rdi         ; *HERE = TOS  (8-byte store)
add rax, 8             ; rax += 8
mov [HERE], rax        ; HERE += 8
mov rdi, [rbp]         ; pop new TOS
add rbp, 8
ret
```

This is the cell-level memory writer.  In Part I we built `,4`
and `,8` (Ch 9) on top of `c,`; the seed's `,` is the same idea
but inlined as a primitive.

## 4. `execute_code` ( xt -- )

```hex0 chunk=execute-code
;; ----- execute_code @ 0x24C -----
48 89 F8
48 8B 7D 00
48 83 C5 08
FF E0

```

```
mov rax, rdi      ; rax = xt
mov rdi, [rbp]    ; pop new TOS (so callee sees the under-TOS as TOS)
add rbp, 8
jmp rax           ; tail-call to the xt
```

`jmp rax` (the two-byte `FF E0`) is an *indirect tail jump*: we
don't `call` and we don't push a return address; the xt sees the
return address that was on top of the return stack when *we* were
called.  When the xt's body executes `ret`, it returns to whoever
called `execute`, not to `execute` itself.

That sounds delicate, but it's exactly the right behaviour: from a
Forth caller's perspective, `execute` is supposed to be transparent
— a way to call a word indirectly.  The tail-jump makes the
indirection cost zero.

## 5. `read_word` — the token reader

```hex0 chunk=read-word
;; ----- read_word @ 0x259 ( -- ; rax = token len, 0 on EOF ) -----
;; Uses rbx (callee-saved across syscalls) for byte count;
;; rcx is clobbered by syscall in key_code.
48 31 DB                                  ; xor rbx, rbx
;; @0x25C: call key_code (rel32 = 0x10C - 0x261 = -341)
E8 AB FE FF FF
48 89 FA                                  ; mov rdx, rdi
48 8B 7D 00                               ; mov rdi, [rbp]
48 83 C5 08                               ; add rbp, 8
48 85 D2                                  ; test rdx, rdx
74 5F                                     ; jz .done
48 83 FA 20                               ; cmp rdx, 0x20
74 E5                                     ; je .skipws
48 83 FA 09                               ; cmp rdx, 0x09
74 DF                                     ; je .skipws
48 83 FA 0A                               ; cmp rdx, 0x0A
74 D9                                     ; je .skipws
48 83 FA 0D                               ; cmp rdx, 0x0D
74 D3                                     ; je .skipws
88 14 25 00 28 41 00                      ; mov [0x412800], dl
48 C7 C3 01 00 00 00                      ; mov rbx, 1
;; @0x297: call key_code (rel32 = 0x10C - 0x29C = -400)
E8 70 FE FF FF
48 89 FA
48 8B 7D 00
48 83 C5 08
48 85 D2
74 24
48 83 FA 20
74 1E
48 83 FA 09
74 18
48 83 FA 0A
74 12
48 83 FA 0D
74 0C
88 14 1D 00 28 41 00                      ; mov [0x412800 + rbx], dl
48 FF C3                                  ; inc rbx
EB C7
48 89 D8                                  ; mov rax, rbx
C3

```

The algorithm: read bytes from `key` until we find a non-whitespace
byte (or EOF), then keep reading until we hit whitespace or EOF,
copying the bytes into the token buffer at `0x412800`.  Return the
token length in `rax`.

The implementation has *two* loops because the first one (skip
leading whitespace) is structurally different from the second one
(accumulate non-whitespace).  The first treats EOF as "return 0";
the second treats EOF as "you reached the end mid-token, return what
you have."

`rbx` is used as the byte-count accumulator because the seed's
`key` calls `syscall` directly and `syscall` clobbers `rcx` and
`r11`.  `rbx` is callee-saved (the kernel preserves it), so the
count survives the syscall.

The two `call key_code` sites use 32-bit relative displacements
computed by hand.  This is the first time in Part II that we see
a `CALL` inside a primitive body — `read_word` itself is a Forth
primitive that calls another primitive.

## 6. `state_code` and `latest_code`

```hex0 chunk=state-code
;; ----- state_code @ 0x753 ( -- addr ) push absolute address of STATE sysvar -----
;; Sysvar layout (from header line 40): STATE/LATEST/HERE/LAST_FOUND/NUMBER_HOOK/INPUT_FD
;; live at 0x413000+8N. This pushes 0x413000 (= STATE).
48 83 ED 08                               ; sub rbp, 8         ; make data-stack room
48 89 7D 00                               ; mov [rbp], rdi     ; spill old TOS
48 BF 00 30 41 00 00 00 00 00             ; movabs rdi, 0x413000  ; = &STATE
C3                                        ; ret

```

```hex0 chunk=latest-code
;; ----- latest_code @ 0x766 ( -- addr ) push absolute address of LATEST sysvar -----
48 83 ED 08                               ; sub rbp, 8         ; make data-stack room
48 89 7D 00                               ; mov [rbp], rdi     ; spill old TOS
48 BF 08 30 41 00 00 00 00 00             ; movabs rdi, 0x413008  ; = &LATEST
C3                                        ; ret

```

Both follow the same shape: spill old TOS, then load a 64-bit
constant into `rdi`.  The constant is the *address* of the sysvar,
so the caller does `state @` to read or `state !` to write.

These are the seed's reflection hatches.  Once you have the address
of a sysvar, you can read it, write it, atomically check-and-update
it.  Anything the runtime exposes via STATE or LATEST becomes
mutable Forth-level state.

## 7. `tick_code` — the name lookup hatch

```hex0 chunk=tick-code
;; ----- tick_code @ 0x779 ( -- xt ) read next word and look up its xt -----
;; Calls read_word to fill TIB and return token length in rax.
;; Then sets up find_code's calling convention: pushes (TIB, len) onto the
;; data stack with len in rdi and TIB at [rbp]. Mirrors the repl pattern at
;; lines 296-307 (the repl's read_word + find_code sequence).
;;
;; Returns 0 in rdi if word not found -- find_code already does `xor rdi,rdi; ret`
;; on miss (lines 189-190), so we inherit that behavior for free.
;;
;; @0x779: call read_word (rel32 = 0x259 - 0x77E = -1317)
E8 DB FA FF FF
48 83 ED 08                               ; sub rbp, 8         ; make room for spilled TOS
48 89 7D 00                               ; mov [rbp], rdi     ; spill old TOS
48 C7 C7 00 28 41 00                      ; mov rdi, 0x412800  ; rdi = c-addr (TIB)
48 83 ED 08                               ; sub rbp, 8         ; make room to spill c-addr
48 89 7D 00                               ; mov [rbp], rdi     ; [rbp] = c-addr
48 89 C7                                  ; mov rdi, rax       ; rdi = u (token len)
;; @0x798: call find_code (rel32 = 0x1C5 - 0x79D = -1496)
E8 28 FA FF FF
C3                                        ; ret  ; rdi = xt (or 0 if not found)

```

`'` reads a token, looks it up, and pushes the xt.  The
implementation reuses `read_word` and `find_code`; it just has to
shuffle the data stack so `find_code` sees its expected `( c-addr u
-- )` shape.

After `read_word`, the token length is in `rax` and the token bytes
are in the buffer at `0x412800`.  `tick_code` spills the current
TOS, pushes the buffer address (`0x412800`), spills *that*, then
loads the length into `rdi` as TOS.  Now the stack is `( ...old c-
addr len )` and we can call `find_code`, which consumes both cells
and pushes the xt (or 0) as new TOS.

The chained-call pattern (`call A; setup; call B; ret`) is
characteristic of Forth-primitive composition.  `tick_code` is the
seed's smallest example.

## 8. The dictionary entries

The 24 entries from `bye` to `0branch` live in one contiguous block
running from `0x44D` to `0x5F8`.  Each is 14–18 bytes; the whole
block is 167 lines of hex.  Rather than chunk each separately, we
ship them as one big chunk that the master root block references
once.

```hex0 chunk=dictionary-entries
;; --- bye @ 0x44D (xt = 0x45A) ---
00 00 00 00 00 00 00 00
00
03
62 79 65
E9 73 FC FF FF                              ; jmp bye_code (rel = 0x0D2 - 0x45F = -909)

;; --- emit @ 0x45F (xt = 0x46D) ---
4D 04 40 00 00 00 00 00
00
04
65 6D 69 74
E9 6C FC FF FF                              ; jmp emit_code (rel = 0x0DE - 0x472 = -916)

;; --- key @ 0x472 (xt = 0x47F) ---
5F 04 40 00 00 00 00 00
00
03
6B 65 79
E9 88 FC FF FF                              ; jmp key_code (rel = 0x10C - 0x484 = -888)

;; --- dup @ 0x484 (xt = 0x491) ---
72 04 40 00 00 00 00 00
00
03
64 75 70
E9 A5 FC FF FF                              ; jmp dup_code (rel = 0x13B - 0x496 = -859)

;; --- drop @ 0x496 (xt = 0x4A4) ---
84 04 40 00 00 00 00 00
00
04
64 72 6F 70
E9 9B FC FF FF                              ; jmp drop_code (rel = 0x144 - 0x4A9 = -869)

;; --- swap @ 0x4A9 (xt = 0x4B7) ---
96 04 40 00 00 00 00 00
00
04
73 77 61 70
E9 91 FC FF FF                              ; jmp swap_code (rel = 0x14D - 0x4BC = -879)

;; --- >r @ 0x4BC (xt = 0x4C8) ---
A9 04 40 00 00 00 00 00
00
02
3E 72
E9 8C FC FF FF                              ; jmp to_r_code (rel = 0x159 - 0x4CD = -884)

;; --- r> @ 0x4CD (xt = 0x4D9) ---
BC 04 40 00 00 00 00 00
00
02
72 3E
E9 87 FC FF FF                              ; jmp r_from_code (rel = 0x165 - 0x4DE = -889)

;; --- @ @ 0x4DE (xt = 0x4E9) ---
CD 04 40 00 00 00 00 00
00
01
40
E9 83 FC FF FF                              ; jmp fetch_code (rel = 0x171 - 0x4EE = -893)

;; --- ! @ 0x4EE (xt = 0x4F9) ---
DE 04 40 00 00 00 00 00
00
01
21
E9 77 FC FF FF                              ; jmp store_code (rel = 0x175 - 0x4FE = -905)

;; --- c@ @ 0x4FE (xt = 0x50A) ---
EE 04 40 00 00 00 00 00
00
02
63 40
E9 7A FC FF FF                              ; jmp cfetch_code (rel = 0x189 - 0x50F = -902)

;; --- c! @ 0x50F (xt = 0x51B) ---
FE 04 40 00 00 00 00 00
00
02
63 21
E9 6E FC FF FF                              ; jmp cstore_code (rel = 0x18E - 0x520 = -914)

;; --- + @ 0x520 (xt = 0x52B) ---
0F 05 40 00 00 00 00 00
00
01
2B
E9 71 FC FF FF                              ; jmp plus_code (rel = 0x1A1 - 0x530 = -911)

;; --- nand @ 0x530 (xt = 0x53E) ---
20 05 40 00 00 00 00 00
00
04
6E 61 6E 64
E9 67 FC FF FF                              ; jmp nand_code (rel = 0x1AA - 0x543 = -921)

;; --- 0= @ 0x543 (xt = 0x54F) ---
30 05 40 00 00 00 00 00
00
02
30 3D
E9 62 FC FF FF                              ; jmp zeq_code (rel = 0x1B6 - 0x554 = -926)

;; --- find @ 0x554 (xt = 0x562) ---
43 05 40 00 00 00 00 00
00
04
66 69 6E 64
E9 5E FC FF FF                              ; jmp find_code (rel = 0x1C5 - 0x567 = -930)

;; --- here @ 0x567 (xt = 0x575) ---
54 05 40 00 00 00 00 00
00
04
68 65 72 65
E9 A1 FC FF FF                              ; jmp here_code (rel = 0x21B - 0x57A = -863)

;; --- , @ 0x57A (xt = 0x585) ---
67 05 40 00 00 00 00 00
00
01
2C
E9 A2 FC FF FF                              ; jmp comma_code (rel = 0x22C - 0x58A = -862)

;; --- execute @ 0x58A (xt = 0x59B) ---
7A 05 40 00 00 00 00 00
00
07
65 78 65 63 75 74 65
E9 AC FC FF FF                              ; jmp execute_code (rel = 0x24C - 0x5A0 = -852)

;; --- : @ 0x5A0 (xt = 0x5AB) ---
8A 05 40 00 00 00 00 00
00
01
3A
E9 24 FD FF FF                              ; jmp colon_code (rel = 0x2D4 - 0x5B0 = -732)

;; --- ; @ 0x5B0 (xt = 0x5BB) ---  IMMEDIATE
A0 05 40 00 00 00 00 00
01
01
3B
E9 7B FD FF FF                              ; jmp semicolon_code (rel = 0x33B - 0x5C0 = -645)

;; --- lit @ 0x5C0 (xt = 0x5CD) ---
B0 05 40 00 00 00 00 00
00
03
6C 69 74
E9 47 FE FF FF                              ; jmp lit_code (rel = 0x419 - 0x5D2 = -441)

;; --- branch @ 0x5D2 (xt = 0x5E2) ---
C0 05 40 00 00 00 00 00
00
06
62 72 61 6E 63 68
E9 44 FE FF FF                              ; jmp branch_code (rel = 0x42B - 0x5E7 = -444)

;; --- 0branch @ 0x5E7 (xt = 0x5F8) ---
D2 05 40 00 00 00 00 00
00
07
30 62 72 61 6E 63 68
E9 34 FE FF FF                              ; jmp zbranch_code (rel = 0x431 - 0x5FD = -460)

```

A few things to notice as your eye walks down the chunk:

- **Every link cell points 14–18 bytes back** — the size of the
  previous entry.  Adding a new primitive means: append a new
  entry, set its `link` to the address of the previous entry's
  link cell, and patch the seed-time constant `LATEST` (in
  `<<sysvar-init>>`).
- **The flags byte is `00` for everyone except `;`.**  Only `;`
  carries `flags = 01` (IMMEDIATE); the REPL checks that bit
  before deciding to compile vs execute.
- **The body is always five bytes: `E9 xx xx xx xx`** — a `JMP
  rel32` back to the primitive's code.  This is what makes the
  headers and bodies layout-independent.

## 9. The late dictionary entries

After the seed's growth — adding `r@`, `*`, `state`, `latest`,
`'` — five more entries sit at the very end of the file.  Each
chains back through the previous `late` entry's link, and the very
last entry (`'`) is the one `LATEST` is initialised to point at
(see Ch 13's `<<sysvar-init>>`).

```hex0 chunk=late-dicts
;; --- r@ @ 0x79E (xt = 0x7AA) ---
22 07 40 00 00 00 00 00                     ; link = 0x400722 (/)
00                                        ; flags
02                                        ; nlen
72 40                                     ; "r@"
E9 83 FF FF FF                              ; jmp r_at_code (rel = 0x732 - 0x7AF = -125)

;; --- * @ 0x7AF (xt = 0x7BA) ---
9E 07 40 00 00 00 00 00                     ; link = 0x40079E (r@)
00
01
2A                                        ; "*"
E9 84 FF FF FF                              ; jmp star_code (rel = 0x743 - 0x7BF = -124)

;; --- state @ 0x7BF (xt = 0x7CE) ---
AF 07 40 00 00 00 00 00                     ; link = 0x4007AF (*)
00
05
73 74 61 74 65                            ; "state"
E9 80 FF FF FF                              ; jmp state_code (rel = 0x753 - 0x7D3 = -128)

;; --- latest @ 0x7D3 (xt = 0x7E3) ---
BF 07 40 00 00 00 00 00                     ; link = 0x4007BF (state)
00
06
6C 61 74 65 73 74                         ; "latest"
E9 7E FF FF FF                              ; jmp latest_code (rel = 0x766 - 0x7E8 = -130)

;; --- ' @ 0x7E8 (xt = 0x7F3) ---  <-- LATEST
D3 07 40 00 00 00 00 00                     ; link = 0x4007D3 (latest)
00
01
27                                        ; "'"
E9 81 FF FF FF                              ; jmp tick_code (rel = 0x779 - 0x7F8 = -127)
```

(`<<late-dicts>>` has no trailing blank because it is the last chunk
in the file.)

## Try it

```sh
./build.sh

# Find a known word, get its xt, execute:
echo "' emit [lit] 65 swap execute bye" | ./seed-forth
# Expected: prints "A".  ' returns emit's xt, then 65 swap execute calls it.

# Force a miss; the REPL prints '?':
echo 'wibble' | ./seed-forth
# prints "?"

# Walk the chain by hand.  The seed has no `.`, so peek by treating
# the byte at LATEST as a small number and adding 48 to land in ASCII:
echo "latest @ c@ [lit] 48 + emit bye" | ./seed-forth
# prints the first byte of (LATEST @)'s link cell, as a digit.
```

## Exercises

1. **★★** The dictionary is a singly linked list, newest-to-oldest.  Why
   not oldest-to-newest?  (Hint: `find` checks the most recent
   definition first — shadowing is free.)

2. **★★** Why does `find_code` write to `LAST_FOUND` instead of returning
   both the xt *and* the flag byte on the stack?  (Hint: the REPL
   needs both, but the rare interpret-mode lookup doesn't.  Count
   instructions in each design.)

3. **★★** The `' emit execute` pattern uses `'` to push the xt and
   `execute` to call it.  Trace the data stack and the return stack
   for `[lit] 65 ' emit execute`.  Where does `emit`'s `ret` land?

4. **★★★** Modify `read_word` (in a copy of `000-seed.hex0`) to recognise
   `\` as a line-comment marker that skips until newline.  How many
   extra bytes?  Where in `read_word` does the change go?

5. **★★** Walk the dictionary backwards by hand starting from `LATEST @`
   (= `0x4007E8`, the `'` entry's link cell).  Follow eight link
   cells.  What's the name at each step?

## Takeaways

- The dictionary is the seed's only data structure: a singly linked
  list of headers walked by `find_code`.  No hash, no symbol table.
- `find_code` does name comparison inline in 86 bytes.  Forth-level
  code (`bytes-eq`, Ch 12) re-implements the same logic in 13 lines.
- `read_word`, `find_code`, `'`, `execute` together are the
  metacompiler hatch: from a token, you can reach an xt; from an
  xt, you can call the word.

Next: Chapter 18 — The Colon Compiler.
