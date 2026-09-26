# Chapter 17 — The Dictionary

```text
Missing capability: how find, ', and execute actually work is unknown.
New pattern: a singly-linked list of [link][flags][name-len][name-bytes][body] entries, scanned newest-first.
Artifact after this chapter: the dictionary's layout and its lookup primitive in machine code.
Proof link: "small tables, linear search, newest wins" first appears here; Chs 22, 24, 30, 31 reapply it.
```

Every word the seed knows, from `bye` to `'`, and every word `:`
adds later, lives in one singly linked list.  There is no hash
table, no symbol table and no environment frame.  This chapter reads
that list and the primitives that build and search it.

The code sits in three bands of `000-seed.hex0`.  Lines 171–262 hold
`find_code`, `here_code`, `comma_code`, `execute_code` and
`read_word`.  Lines 387–554 are the hand-laid dictionary entries for
every primitive from `bye` through `0branch`.  Lines 684–752 close
the file with `state_code`, `latest_code` and `tick_code`, plus the
entries for `r@`, `*`, `state`, `latest` and `'`.

§§1–4 cover the header layout, the lookup, and the primitives that
build entries (`here`, `,`) and run them (`execute`); §§1–2 stand on
their own if you only want the lookup algorithm.  §§5–7 cover the
token reader and the sysvar accessors the REPL relies on.  §§8–9
list the entries themselves.  The REPL's use of `find_code` and
`execute_code` is Ch 20, and `[lit]`'s IMMEDIATE entry is Ch 18.

The list grows forward (new entries go at `HERE`) but is searched
backward (from `LATEST`), so the most recent definition is the
first one a lookup finds.  Redefine `dup` and the new entry matches
first; the original becomes invisible.

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

The seed contains 32 hand-laid headers.  Twenty-four sit in one
block, from `bye` at `0x44D` through `0branch` at `0x5E7`; the other
eight are scattered among the bodies near the end of the file.

Here is `dup`'s entry laid out byte by byte, with the path a
compiled call to `dup` takes at runtime:

```text
dup's entry: file offset 0x484, virtual address 0x400484

field    link (8 bytes)             flags   nlen    name       body (5 bytes)
        +--------------------------+-------+-------+----------+----------------+
bytes   | 72 04 40 00 00 00 00 00  |  00   |  03   | 64 75 70 | E9 A5 FC FF FF |
        +--------------------------+-------+-------+----------+----------------+
offset   +0                         +8      +9      +10        +13 = 10 + nlen
address  0x484                      0x48C   0x48D   0x48E      0x491  <-- xt
meaning  0x400472 = key's entry     not IMM 3       "dup"      JMP dup_code

A compiled call to dup, at runtime:

  caller   E8 rel32          CALL 0x400491     (dup's xt: the JMP stub)
                |
                v
  0x491    E9 A5 FC FF FF    JMP  0x40013B     (rel32 = 0x13B - 0x496 = -859)
                |
                v
  0x13B    dup_code          sub rbp, 8 / mov [rbp], rdi / ret
                |
                v
  ret lands on the instruction after the caller's CALL
```

Each header's `link` points at the *previous header's link cell*.
The first header (`bye`) has `link = 0`.  At runtime, the sysvar
`LATEST` points at the most recent entry's link cell.

The `body` of every hand-laid header is a 5-byte `JMP rel32` to the
primitive's code, so a header and its body can sit anywhere in the
file relative to each other.  That stub *is* the word's execution
token.  For a seed primitive the xt is the address of the `E9` byte
in its header.  Take `dup` as an example.  Its xt is `0x400491`,
not `dup_code` at `0x40013B`.  A compiled call runs `CALL xt`, then `JMP`, then the
primitive's code, and the primitive's `ret` comes straight back to
the caller.  For words you define with `:`, the xt is the first byte
of the compiled body.  From here on, "xt" means exactly this address.

Following the links from `LATEST` visits every entry, newest first:

```text
LATEST = 0x4007E8
  |
  v
'  @ 0x7E8 -> latest @ 0x7D3 -> state @ 0x7BF -> *  @ 0x7AF -> r@ @ 0x79E
  -> /  @ 0x722 -> syscall6 @ 0x6F9 -> [lit] @ 0x6C0 -> 0branch @ 0x5E7
  -> ... -> key @ 0x472 -> emit @ 0x45F -> bye @ 0x44D -> 0 (end of chain)
```

`find` walks this chain.  Each step is one load of the link cell.
Lookup compares the name bytes; on a match it returns, on a mismatch
it follows the link.  A link of `0` means the chain is exhausted and
the lookup misses.

This is the first instance of "small tables, linear search, newest
wins": no index, and shadowing comes free because the reverse walk
sees the newest definition first.

## 2. `find_code` ( c-addr u -- xt-or-0 )

86 bytes of machine code, and the densest routine in the seed.  It
is not the biggest: `read_word` (123 bytes), `colon_code` (103),
`bracket_lit_code` (110) and the REPL loop (187) are all larger.

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
  mov al, [r8]
  cmp al, [r9]
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

The hex holds all of this (outer loop, byte-compare inner loop, hit
path and miss path) in 86 bytes.  Three details stand out.

**`LAST_FOUND` is a side channel.**  On a hit, `find_code` stores
the address of the matched entry's link cell into the sysvar at
`0x413018`.  The REPL (Ch 20) reads this on every hit to check
the IMMEDIATE bit before deciding whether to call-now or emit-a-
call-instruction.  Returning just the xt isn't enough; the *flag
byte* sits one cell past the link, and the caller needs both.

**The body address is `[rcx+10+nlen]`.**  Right at the moment of
hit, `r8` has been advancing through the name bytes (one byte per
loop iteration), so when `rdx` hits zero `r8` is sitting at the
first byte *after* the name, which is the start of the body.  The
answer is already in `r8`, with no extra arithmetic.

**The exits are tails.**  `.hit`, `.skip` and `.miss` sit after
the inner loop, in that order; `.miss` is the last two lines of the
routine (lines 197–198 of `000-seed.hex0`).  Every branch is a
2-byte `rel8` jump, and in an 86-byte routine any target is in
reach, so the order is not forced.  Each exit ends in its own `ret`
(or a jump back to `.next`), so none falls through into another.

## 3. `here_code` and `comma_code`

`here_code` returns the *contents* of the HERE sysvar: the
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

That is what a Forth caller wants: `execute` should be a transparent
indirect call with no frame of its own, and the tail jump makes the
indirection free.

## 5. `read_word`, the token reader

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
computed by hand.  `read_word` is the first body in Part II that
calls another primitive.

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
so the caller does `state @` to read or `state !` to write.  (The
source comment's "header line 40" is stale: the sysvar layout note
is at line 48 of `000-seed.hex0`.)

These two words expose the seed's own state to Forth.  With the
address of STATE or LATEST, Forth code can read or change the mode
and the head of the dictionary, which is how `010-lib.fth` builds
`immediate` (Ch 10).

## 7. `tick_code`: from name to xt

```hex0 chunk=tick-code
;; ----- tick_code @ 0x779 ( -- xt ) read next word and look up its xt -----
;; Calls read_word to fill TIB and return token length in rax.
;; Then sets up find_code's calling convention: pushes (TIB, len) onto the
;; data stack with len in rdi and TIB at [rbp]. Mirrors the repl pattern
;; (the repl's read_word + find_code sequence).
;;
;; Returns 0 in rdi if word not found -- find_code already does `xor rdi,rdi; ret`
;; on miss, so we inherit that behavior for free.
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

`tick_code` is the seed's smallest example of composing primitives
by chained calls: `call A; setup; call B; ret`.

## 8. The dictionary entries

The 24 entries from `bye` to `0branch` form one contiguous block
from `0x44D` to `0x5FD`, each 16–22 bytes long.  They appear below
as one chunk, `<<dictionary-entries>>`, split into four listings by
the chapter that explains each word's body.

The I/O words come first.  `bye` ends the chain with a zero link.
The next entry's link cell holds `4D 04 40 00 00 00 00 00`, which
read little-endian is `0x40044D`, the start of `bye`'s entry.

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

```

Every link cell points back by the size of the previous entry.
Adding a primitive means appending an entry, setting its `link` to
the previous entry's address, and patching the assembly-time value
of `LATEST` in `<<sysvar-init>>`.

The stack and memory words of Ch 14:

```hex0 chunk=dictionary-entries
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

```

The arithmetic words of Ch 15, then the four dictionary primitives
from §§2–4 of this chapter:

```hex0 chunk=dictionary-entries
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

```

The colon compiler (Ch 18) and the inline-cell words (Chs 18–19).
The flags byte is `00` for every entry here except `;`, which
carries `01` (IMMEDIATE) so the REPL runs it instead of compiling a
call to it:

```hex0 chunk=dictionary-entries
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

## 9. The late dictionary entries

Five more entries close the file: `r@`, `*`, `state`, `latest` and
`'`.  The first links back to `/` at `0x722`, each later one links
to the entry before it, and the last (`'`) is where `LATEST` starts
(Ch 13's `<<sysvar-init>>`).

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

# Walk the chain by hand.  The seed has no `.`, so peek at the
# name-length byte (offset 9 in the header layout above) and add 48
# to land in ASCII:
echo "latest @ [lit] 9 + c@ [lit] 48 + emit bye" | ./seed-forth
# prints the most-recent word's name length as a digit.  The seed's
# newest word is `'`, a one-character name, so this prints "1".
```

## Exercises

1. **★★ Trace.** The dictionary is a singly linked list, newest-to-oldest.  Why
   not oldest-to-newest?  (Hint: `find` checks the most recent
   definition first — shadowing is free.)

2. **★★ Trace.** Why does `find_code` write to `LAST_FOUND` instead of returning
   both the xt *and* the flag byte on the stack?  (Hint: the REPL
   reads `LAST_FOUND` on every hit, in both modes, to test the
   IMMEDIATE bit — but `'` and Forth-level `find` want only the
   xt.  Count instructions in each design.)

3. **★★ Trace.** The `' emit execute` pattern uses `'` to push the xt and
   `execute` to call it.  Trace the data stack and the return stack
   for `[lit] 65 ' emit execute`.  Where does `emit`'s `ret` land?

4. **★★★ Modify.** Modify `read_word` (in a copy of `000-seed.hex0`) to recognise
   `\` as a line-comment marker that skips until newline.  How many
   extra bytes?  Where in `read_word` does the change go?

5. **★★ Trace.** Walk the dictionary backwards by hand starting from `LATEST @`
   (= `0x4007E8`, the `'` entry's link cell).  Follow eight link
   cells.  What's the name at each step?

## Takeaways

- The dictionary is the seed's only data structure: a singly linked
  list of headers searched newest-first, which is what lets a
  redefinition shadow the old word.
- `find_code` compares names inline in 86 bytes and records the
  matched entry in `LAST_FOUND` so the REPL can test its IMMEDIATE
  flag.
- A seed primitive's xt is the 5-byte `JMP` stub at the end of its
  header, and `'` plus `execute` turn a name into a call through it.

Next: Chapter 18 — The Colon Compiler.
