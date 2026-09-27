# Chapter 17 — The Dictionary

```text
Missing capability: how find, ', and execute actually work is unknown, and so is how a token gets off stdin.
New pattern: a singly-linked list of [link][flags][name-len][name-bytes][code] entries, scanned newest-first.
Artifact after this chapter: the dictionary's layout, its lookup primitive, and the token reader, in machine code.
Proof link: "small tables, linear search, newest wins" first appears here; Chs 22, 24, 30, 31 reapply it.
```

Ask the seed for `dup` with `' dup` and it pushes `0x4000C7`, the
address of `dup_code`'s first instruction.  The seed stores that
address nowhere.  It has no table of code pointers and no pointer
field in any header.  It finds the code the same way it finds a
word's name: `dup`'s header is 13 bytes long, and the code starts at
the 14th.  Every word works like this, the seed's 32 and every one
`:` adds later, and by the end of §2 you will see why that one rule
keeps the lookup, `execute` and the compiler free of special cases.

The list those headers form is the dictionary, and it is the seed's
only data structure.  Every word the seed knows, from `dup` to
`0branch`, and every word `:` adds later, lives in one singly linked
list: no hash table, no symbol table, no environment frame.  It
grows forward (new entries go at `HERE`) but is searched backward
(from `LATEST`), so redefine `dup` and the new entry matches first.

This chapter reads lines 320–513 of `000-seed.hex0`: `find`, `here`,
`,` and `execute`; then `read_word`, the routine that turns stdin
into tokens, with its three helpers; then `state`, `latest` and `'`.
§§1–2 (layout and lookup) stand on their own; §§3–4 read the
primitives that build and run entries; §§5–7 read the token reader,
including the part that skips comments and the part that complains;
§§8–9 name entries; §10 walks the whole chain.

## 1. The header layout

Each dictionary entry is:

```
offset  size  field
   0     8    link        — address of previous entry's link cell, or 0
   8     1    flags       — bit 0 = IMMEDIATE
   9     1    nlen        — name length in bytes
  10     N    name        — N bytes of the word's name (ASCII)
 10+N    M    code        — machine code for the word
```

The seed contains 32 hand-laid headers, one in front of each
primitive's code, and every word `:` defines later gets the same
shape.  Here is `drop`'s entry laid out byte by byte, with the path
a compiled call to `drop` takes at runtime:

```text
drop's entry: file offset 0x0D0, virtual address 0x4000D0

field    link (8 bytes)            flags  nlen  name         code (9 bytes)
        +-------------------------+------+-----+------------+----------------------------+
bytes   | BA 00 40 00 00 00 00 00 |  00  |  04 | 64 72 6F 70 | 48 8B 7D 00 48 83 C5 08 C3 |
        +-------------------------+------+-----+------------+----------------------------+
offset   +0                        +8     +9    +10          +14 = 10 + nlen
address  0x0D0                     0x0D8  0x0D9 0x0DA        0x0DE  <-- xt
meaning  0x4000BA = dup's entry    not IMM 4    "drop"       drop_code

A compiled call to drop, at runtime:

  caller   E8 rel32          CALL 0x4000DE     (drop's xt: the first byte of drop_code)
                |
                v
  0x0DE    drop_code         mov rdi, [rbp] / add rbp, 8 / ret
                |
                v
  ret lands on the instruction after the caller's CALL
```

Each header's `link` points at the *previous header's link cell*.
The first header (`dup`) has `link = 0`.  At runtime, the sysvar
`LATEST` points at the most recent entry's link cell.

The word's **execution token** (xt) is the address of the first
byte after its name: for `drop`, `0x4000DE`, which is exactly where
`drop_code` begins.  A compiled call runs `CALL xt`, the code runs,
and its `ret` comes straight back to the caller.  For words you
define with `:`, the xt is likewise the first byte of the compiled
body.  From here on, "xt" means exactly this address.

Following the links from `LATEST` visits every entry, newest first;
§10 walks the whole chain.  `find` walks it one link-cell load per
step, comparing names until one matches or a link of `0` ends the
search.

This is the first instance of "small tables, linear search, newest
wins": no index, and shadowing comes free because the reverse walk
sees the newest definition first.

## 2. `find_code` ( c-addr u -- xt-or-0 )

86 bytes of machine code, and the densest routine in the seed.  It
is not the biggest: `read_word` (117 bytes) is larger.  Here is
`find`'s header and code:

```hex0 chunk=find
;; --- find @ 0x2F5 --- header
BE 02 40 00 00 00 00 00                   ; link  = 0x4002BE (syscall6)
00                                        ; flags = 0
04                                        ; nlen  = 4
66 69 6E 64                               ; name  = "find"
;; ----- find_code @ 0x303  ( c-addr u -- xt | 0 ) -----
;; Walks the chain from LATEST.  On a hit, stores the entry's address in
;; LAST_FOUND (the REPL reads its flags byte) and returns the xt: the
;; first byte after the name, which is where the word's code starts.
48 8B 75 00                               ; mov rsi, [rbp]     ; rsi = c-addr
48 83 C5 08                               ; add rbp, 8         ; pop it; rdi = u
48 8B 0C 25 08 30 41 00                   ; mov rcx, [LATEST]  ; rcx = newest entry
;; .next:
48 85 C9                                  ; test rcx, rcx
74 3D                                     ; jz .miss  (rel8 = 0x355 - 0x318)      ; link 0: end of chain
48 0F B6 41 09                            ; movzx rax, byte [rcx+9] ; nlen
48 39 F8                                  ; cmp rax, rdi
75 2E                                     ; jne .skip  (rel8 = 0x350 - 0x322)     ; lengths differ
48 89 FA                                  ; mov rdx, rdi       ; rdx = bytes left to compare
4C 8D 41 0A                               ; lea r8, [rcx+10]   ; r8 = entry's name
49 89 F1                                  ; mov r9, rsi        ; r9 = token
;; .bcmp:
48 85 D2                                  ; test rdx, rdx
74 13                                     ; jz .hit  (rel8 = 0x344 - 0x331)       ; every byte matched
41 8A 00                                  ; mov al, [r8]
41 3A 01                                  ; cmp al, [r9]
75 17                                     ; jne .skip  (rel8 = 0x350 - 0x339)
49 FF C0                                  ; inc r8
49 FF C1                                  ; inc r9
48 FF CA                                  ; dec rdx
EB E8                                     ; jmp .bcmp  (rel8 = 0x32C - 0x344)
;; .hit:
48 89 0C 25 18 30 41 00                   ; mov [LAST_FOUND], rcx
4C 89 C7                                  ; mov rdi, r8        ; xt = byte after the name
C3                                        ; ret
;; .skip:
48 8B 09                                  ; mov rcx, [rcx]     ; follow the link
EB BE                                     ; jmp .next  (rel8 = 0x313 - 0x355)
;; .miss:
48 31 FF                                  ; xor rdi, rdi       ; not found: 0
C3                                        ; ret

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
.hit:
  mov [LAST_FOUND], rcx     ; record entry address for caller
  mov rdi, r8               ; r8 currently points at end of name = start of code
  ret
.skip:
  mov rcx, [rcx]            ; advance to the previous entry
  jmp .next
.miss:
  xor rdi, rdi              ; return 0
  ret
```

Three details stand out.

**`LAST_FOUND` is a side channel.**  On a hit, `find_code` stores
the address of the matched entry's link cell into the sysvar at
`0x413018`.  The REPL (Ch 20) reads this on every hit to check
the IMMEDIATE bit before deciding whether to call-now or emit-a-
call-instruction.  Returning just the xt isn't enough; the *flag
byte* sits one cell past the link, and the caller needs both.

**The xt is `rcx+10+nlen`.**  Right at the moment of hit, `r8` has
been advancing through the name bytes (one byte per loop
iteration), so when `rdx` hits zero `r8` is sitting at the first
byte *after* the name.  `find_code` returns that address, with no
extra arithmetic.

That is the answer to the question this chapter opened with.
Because every header, the 32 hand-laid ones and every one `:` lays
down, is followed immediately by the word's code, the byte after
the name is always the word's first instruction.  One rule, "the xt
is the byte after the name", covers every word, and `find`,
`execute` and the REPL's compile path carry no special case for
primitives.  It costs nothing: no pointer field in the header and
no extra jump per call.

**The exits are tails.**  `.hit`, `.skip` and `.miss` sit after
the inner loop, in that order; `.miss` is the last two lines of the
routine (lines 359–360 of `000-seed.hex0`).  Every branch is a
2-byte `rel8` jump, and in an 86-byte routine any target is in
reach, so the order is not forced.  Each exit ends in its own `ret`
(or a jump back to `.next`), so none falls through into another.

## 3. `here_code` and `comma_code`

`here_code` returns the *contents* of the HERE sysvar: the
next-byte-to-write address.

```hex0 chunk=here
;; --- here @ 0x359 --- header
F5 02 40 00 00 00 00 00                   ; link  = 0x4002F5 (find)
00                                        ; flags = 0
04                                        ; nlen  = 4
68 65 72 65                               ; name  = "here"
;; ----- here_code @ 0x367  ( -- addr ) the value of HERE -----
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
48 8B 3C 25 10 30 41 00                   ; mov rdi, [HERE]
C3                                        ; ret

```

A standard push (spill the old TOS, load the new) where the new TOS
is the contents of `[0x413010]`.

`comma_code` writes 8 bytes at HERE and advances HERE by 8.

```hex0 chunk=comma
;; --- , @ 0x378 --- header
59 03 40 00 00 00 00 00                   ; link  = 0x400359 (here)
00                                        ; flags = 0
01                                        ; nlen  = 1
2C                                        ; name  = ","
;; ----- comma_code @ 0x383  ( v -- ) store a cell at HERE, HERE += 8 -----
48 8B 04 25 10 30 41 00                   ; mov rax, [HERE]
48 89 38                                  ; mov [rax], rdi     ; *HERE = v
48 83 C0 08                               ; add rax, 8
48 89 04 25 10 30 41 00                   ; mov [HERE], rax
48 8B 7D 00                               ; mov rdi, [rbp]
48 83 C5 08                               ; add rbp, 8
C3                                        ; ret

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
but inlined as a primitive.  `[lit]` (Ch 18) reuses it to lay down
a literal's cell.

## 4. `execute_code` ( xt -- )

`execute` pops an xt and jumps to it:

```hex0 chunk=execute
;; --- execute @ 0x3A3 --- header
78 03 40 00 00 00 00 00                   ; link  = 0x400378 (,)
00                                        ; flags = 0
07                                        ; nlen  = 7
65 78 65 63 75 74 65                      ; name  = "execute"
;; ----- execute_code @ 0x3B4  ( xt -- ) tail-jump to xt -----
48 89 F8                                  ; mov rax, rdi       ; rax = xt
48 8B 7D 00                               ; mov rdi, [rbp]
48 83 C5 08                               ; add rbp, 8
FF E0                                     ; jmp rax            ; xt's ret returns to our caller

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
called.  When the xt's code executes `ret`, it returns to whoever
called `execute`, not to `execute` itself.

## 5. `read_word`, the token reader

`find_code` needs a name to look up.  `read_word` supplies it, one
whitespace-delimited token at a time from stdin.  It is not a
dictionary word: the REPL, `:`, `[lit]` and `'` call it directly.
It follows the same stack convention as the primitives,
`( -- c-addr u )`: it leaves the token's address (always the token
buffer at `0x412800`) and its length on the data stack, with `u = 0`
meaning end of input.  That is exactly the pair `find` consumes, so
a caller can go straight from one to the other.

```hex0 chunk=read-word
;; ----- read_word @ 0x3C1  ( -- c-addr u ) next token from stdin; u = 0 at EOF -----
;; Not a dictionary word.  Skips whitespace, then copies bytes to the
;; token buffer (TIB, 0x412800) until whitespace or EOF.  The length is
;; kept in rbx, which syscalls preserve and nothing else in the seed
;; writes, so report_token can still find it after find or [lit] fails.
;; A token that is exactly \ skips to the end of the line, and one that
;; is exactly ( skips past the next ); either way reading starts over.
;; A token longer than 255 bytes (too long for nlen) is fatal.
31 DB                                     ; xor ebx, ebx       ; rbx = length = 0
;; .skip_ws:
E8 6E 00 00 00                            ; call read_char  (rel32 = 0x436 - 0x3C8)
74 F9                                     ; je .skip_ws  (rel8 = 0x3C3 - 0x3CA)   ; whitespace: keep skipping
85 D2                                     ; test edx, edx
74 4F                                     ; jz .done  (rel8 = 0x41D - 0x3CE)      ; EOF before a token: u = 0
;; .store:
88 93 00 28 41 00                         ; mov [rbx+0x412800], dl ; TIB[len] = byte
FF C3                                     ; inc ebx
84 FF                                     ; test bh, bh        ; length >= 256?
0F 85 99 00 00 00                         ; jnz fatal_token  (rel32 = 0x477 - 0x3DE) ; too long: report and exit
E8 53 00 00 00                            ; call read_char  (rel32 = 0x436 - 0x3E3)
74 04                                     ; je .end  (rel8 = 0x3E9 - 0x3E5)       ; whitespace ends the token
85 D2                                     ; test edx, edx
75 E5                                     ; jnz .store  (rel8 = 0x3CE - 0x3E9)    ; not EOF: keep the byte
;; .end:
;; The token is complete; dl holds the byte that ended it (0 = EOF).
83 FB 01                                  ; cmp ebx, 1
75 2F                                     ; jne .done  (rel8 = 0x41D - 0x3EE)     ; comment markers are 1 byte long
8A 04 25 00 28 41 00                      ; mov al, [0x412800]
3C 5C                                     ; cmp al, 0x5C       ; '\'
74 14                                     ; je .line_comment  (rel8 = 0x40D - 0x3F9)
3C 28                                     ; cmp al, 0x28       ; '('
75 20                                     ; jne .done  (rel8 = 0x41D - 0x3FD)
;; .paren_comment:
E8 34 00 00 00                            ; call read_char  (rel32 = 0x436 - 0x402)
85 D2                                     ; test edx, edx
74 BB                                     ; jz read_word  (rel8 = 0x3C1 - 0x406)  ; EOF: start over (and return u = 0)
80 FA 29                                  ; cmp dl, 0x29       ; ')'
75 F2                                     ; jne .paren_comment  (rel8 = 0x3FD - 0x40B)
EB B4                                     ; jmp read_word  (rel8 = 0x3C1 - 0x40D) ; comment over: read the next token
;; .line_comment:
80 FA 0A                                  ; cmp dl, 0x0A       ; reached the newline?
74 AF                                     ; je read_word  (rel8 = 0x3C1 - 0x412)  ; comment over: read the next token
85 D2                                     ; test edx, edx
74 AB                                     ; jz read_word  (rel8 = 0x3C1 - 0x416)  ; EOF: start over (and return u = 0)
E8 1B 00 00 00                            ; call read_char  (rel32 = 0x436 - 0x41B)
EB F0                                     ; jmp .line_comment  (rel8 = 0x40D - 0x41D)
;; .done:
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
BF 00 28 41 00                            ; mov edi, 0x412800  ; push c-addr = TIB
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
48 89 DF                                  ; mov rdi, rbx       ; push u
C3                                        ; ret

```

The algorithm: read bytes until one is not whitespace (or EOF), then
keep reading until whitespace or EOF, copying the bytes into the
token buffer at `0x412800`.  Four parts:

**Skip whitespace (`.skip_ws`).**  `read_char` (§6) fetches the next
byte into `dl` and sets the zero flag if it is whitespace, so `je`
loops over blanks.  A zero byte is EOF: with no token yet, jump
straight to `.done` with length 0.

**Store (`.store`).**  Each byte goes to `[rbx+0x412800]`, and `rbx`
counts.  `rbx` is used as the counter because `key` calls `syscall`
directly and `syscall` clobbers `rcx` and `r11`; the kernel
preserves `rbx`.  Nothing else in the seed writes `rbx`, so after
`read_word` returns it still holds the length of the last token
read, a fact §7 uses.  The token ends at whitespace or EOF.

**Too long is fatal.**  A header stores the name length in one
byte, so a name longer than 255 bytes cannot be represented, and a
token that ran on for 2 KiB would run out of the buffer into the
sysvar page.  After each byte, `test bh, bh` checks bits 8–15 of the
count: non-zero means the token has reached 256 bytes, and
`read_word` hands over to `fatal_token` (§7), which prints what it
has and exits.  A token of 255 bytes or fewer is accepted.

**Comments (`.end`).**  Forth source is full of comments, `\ to the
end of the line` and `( stack effects )`, and the seed skips them
itself, so the library and the compiler can be fed to it exactly as
they are written.  A comment marker is a token of its own, one byte
long: after a token is complete, `read_word` checks for a length of
1 and a byte of `\` or `(`.  For `(` it reads on until a `)` byte;
for `\` until a newline, unless the whitespace byte that ended the
`\` token, still in `dl`, was already the newline.  Then it jumps
back to the top and reads the next token, so a comment never
reaches the caller.  EOF inside a comment ends it too, and the
restart then returns length 0.  Only the markers themselves are
recognised: `(foo` or `foo\` are ordinary tokens.

**Return (`.done`).**  Spill the old TOS, push `0x412800`, and make
the length the new TOS.

The two loops and both comment skips call `read_char`, and the
length check jumps to `fatal_token`; every one of those sites uses a
32-bit relative displacement computed by hand.  `read_word` is the first routine in Part II that
calls another.

## 6. `read_char`, one byte and a verdict

```hex0 chunk=read-char
;; ----- read_char @ 0x436  ( -- ) rdx = next input byte (0 at EOF); ZF=1 iff whitespace -----
E8 54 FE FF FF                            ; call key_code  (rel32 = 0x28F - 0x43B) ; ( -- c )
48 89 FA                                  ; mov rdx, rdi       ; rdx = c
48 8B 7D 00                               ; mov rdi, [rbp]
48 83 C5 08                               ; add rbp, 8
80 FA 20                                  ; cmp dl, 0x20       ; space
74 0D                                     ; je .ret  (rel8 = 0x458 - 0x44B)
80 FA 09                                  ; cmp dl, 0x09       ; tab
74 08                                     ; je .ret  (rel8 = 0x458 - 0x450)
80 FA 0A                                  ; cmp dl, 0x0A       ; newline
74 03                                     ; je .ret  (rel8 = 0x458 - 0x455)
80 FA 0D                                  ; cmp dl, 0x0D       ; carriage return
;; .ret:
C3                                        ; ret                ; ret leaves the flags alone

```

`read_char` calls `key`, pops the byte into `rdx`, and compares it
with the four whitespace bytes: space, tab, newline, carriage
return.  The last comparison's flags survive the `ret`, so the
caller's `je` means "that was whitespace".  An EOF `0` compares
unequal to all four, which is why `read_word` follows each `je` with
its own `test edx, edx`.

## 7. `report_token` and `fatal_token`: failing out loud

Three things can go wrong with a token: `find` doesn't know it (the
REPL, Ch 20), `[lit]` can't read it as a number (Ch 18), or it is
too long (§5).  All three answer the same way: print the token,
then `?`, then a newline.  An unknown word goes on to the next
token; the other two are fatal, because continuing would compile
garbage.

```hex0 chunk=report-token
;; ----- report_token @ 0x459  ( -- ) write the last token and '?' newline to stdout -----
;; Uses rbx (the token length).  Clobbers rdi, so callers drop or exit.
66 C7 83 00 28 41 00 3F 0A                ; mov word [rbx+0x412800], 0x0A3F ; append '?' and newline
8D 53 02                                  ; lea edx, [rbx+2]   ; count = len + 2
BE 00 28 41 00                            ; mov esi, 0x412800  ; buf = TIB
B8 01 00 00 00                            ; mov eax, 1         ; SYS_write
BF 01 00 00 00                            ; mov edi, 1         ; fd 1 (stdout)
0F 05                                     ; syscall
C3                                        ; ret

;; ----- fatal_token @ 0x477  ( -- ) report the last token, then exit(2) -----
E8 DD FF FF FF                            ; call report_token  (rel32 = 0x459 - 0x47C)
B8 3C 00 00 00                            ; mov eax, 60        ; SYS_exit
BF 02 00 00 00                            ; mov edi, 2         ; status 2: bad input
0F 05                                     ; syscall

```

`report_token` uses the length in `rbx` that `read_word` left
behind.  Its first instruction writes the two bytes `3F 0A` (`?`
and newline) into the buffer right after the token, so one
`write(1, 0x412800, len + 2)` prints both; the buffer has 2 KiB of
room and a token is at most 256 bytes.  It clobbers `rdi`, the TOS,
so its callers either drop a cell afterwards or never return.

`fatal_token` calls `report_token` and exits with status 2.  Those
two `syscall` instructions, `write` and `exit`, are the two Ch 16
did not read.  Status 2 is the seed's own: no `[lit] 2 die` appears
in the compiler (Appendix G), so a status of 2 while loading Forth
means "the seed rejected a token", and the token is the last thing
it printed.

## 8. `state_code` and `latest_code`

Two tiny primitives hand Forth the addresses of the sysvars the REPL
and `:` depend on:

```hex0 chunk=state
;; --- state @ 0x488 --- header
A3 03 40 00 00 00 00 00                   ; link  = 0x4003A3 (execute)
00                                        ; flags = 0
05                                        ; nlen  = 5
73 74 61 74 65                            ; name  = "state"
;; ----- state_code @ 0x497  ( -- addr ) address of the STATE sysvar -----
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
48 BF 00 30 41 00 00 00 00 00             ; mov rdi, 0x413000  ; &STATE (movabs)
C3                                        ; ret

```

```hex0 chunk=latest
;; --- latest @ 0x4AA --- header
88 04 40 00 00 00 00 00                   ; link  = 0x400488 (state)
00                                        ; flags = 0
06                                        ; nlen  = 6
6C 61 74 65 73 74                         ; name  = "latest"
;; ----- latest_code @ 0x4BA  ( -- addr ) address of the LATEST sysvar -----
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
48 BF 08 30 41 00 00 00 00 00             ; mov rdi, 0x413008  ; &LATEST (movabs)
C3                                        ; ret

```

Both follow the same shape: spill old TOS, then load a 64-bit
constant into `rdi`.  The constant is the *address* of the sysvar,
so the caller does `state @` to read or `state !` to write.  The
comment block above `_start` gives the sysvar layout: `STATE`,
`LATEST`, `HERE`, `LAST_FOUND`, consecutive cells from `0x413000`.

With these two addresses Forth code can change the mode and the head
of the dictionary, which is how `010-lib.fth` builds `immediate`
(Ch 10).  Because the cells are consecutive, the two addresses are
also all the library needs to find the rest: `here-addr` is
`latest [lit] 8 +`, and the page above the sysvars starts at
`state [lit] 4096 +` (Ch 2, Ch 12), so no Forth file types in a seed
address.

## 9. `tick_code`: from name to xt

`'` strings together the pieces from §§2 and 5:

```hex0 chunk=tick
;; --- ' @ 0x4CD --- header
AA 04 40 00 00 00 00 00                   ; link  = 0x4004AA (latest)
00                                        ; flags = 0
01                                        ; nlen  = 1
27                                        ; name  = "'"
;; ----- tick_code @ 0x4D8  ( -- xt | 0 ) read the next token and find it -----
E8 E4 FE FF FF                            ; call read_word  (rel32 = 0x3C1 - 0x4DD) ; ( -- c-addr u )
E9 21 FE FF FF                            ; jmp find_code  (rel32 = 0x303 - 0x4E2) ; ( c-addr u -- xt | 0 ), tail call

```

`read_word` leaves `( c-addr u )` on the stack, which is exactly
what `find_code` consumes, so `'` is one call and one jump: `find`
runs as a tail call, and its `ret` returns straight to whoever
called `'`, with the xt (or 0) as the new TOS.

`tick_code` is the seed's smallest example of composing routines
that share one stack convention: `call A; jmp B`.

## 10. The chain

The 32 headers, one per unit, from `dup` at `0x0BA` to `0branch`
at `0x617`, form one chain.  `LATEST` starts at the last of them
(Ch 13's `<<sysvar-init>>`), and following the links from there
visits every word:

```text
LATEST = 0x400617
  |
  v
0branch @ 0x617 -> branch @ 0x601 -> [lit] @ 0x5B2 -> lit @ 0x593
  -> ; @ 0x53F -> : @ 0x4E2 -> ' @ 0x4CD -> latest @ 0x4AA
  -> state @ 0x488 -> execute @ 0x3A3 -> , @ 0x378 -> here @ 0x359
  -> find @ 0x2F5 -> syscall6 @ 0x2BE -> key @ 0x282 -> emit @ 0x246
  -> bye @ 0x22D -> * @ 0x212 -> / @ 0x1F5 -> 0= @ 0x1DA
  -> nand @ 0x1C0 -> + @ 0x1AC -> c! @ 0x18D -> c@ @ 0x17C
  -> ! @ 0x15D -> @ @ 0x14E -> r@ @ 0x131 -> r> @ 0x119
  -> >r @ 0x101 -> swap @ 0x0E7 -> drop @ 0x0D0 -> dup @ 0x0BA
  -> 0 (end of chain)
```

Each link cell holds the address of the header before it; `drop`'s
holds `BA 00 40 00 00 00 00 00`, which read little-endian is
`0x4000BA`, the start of `dup`'s header.  The four routines without
names, `read_word`, `read_char`, `report_token` and `fatal_token`,
sit between `execute` and `state` in the file but have no header,
so the chain steps straight over them.  Adding a primitive means
inserting a unit, pointing its `link` at the header before it and
the next header's `link` at it, recomputing every address that moved
and, if it is the new last word, patching the assembly-time value of
`LATEST` in `<<sysvar-init>>`.

The headers take 421 of the seed's 1,772 bytes: 32 × 10 bytes of
link, flags and length, plus 101 bytes of names.

## Canonical source

This chapter's ten chunks, `<<find>>` through `<<tick>>`, are
defined inline in the prose above, in the order the master root
block in Ch 13 lists them.

## Try it

```sh
./build.sh

# Find a known word, get its xt, execute:
echo "' emit [lit] 65 swap execute bye" | ./seed-forth
# Expected: prints "A".  ' returns emit's xt, then 65 swap execute calls it.

# Force a miss; the REPL echoes the token with a '?':
echo 'wibble' | ./seed-forth
# prints "wibble?"

# Comments never reach the REPL:
echo '[lit] 67 ( a stack comment ) emit \ a line comment' | ./seed-forth
# prints "C"

# Walk the chain by hand.  The seed has no `.`, so peek at the
# name-length byte (offset 9 in §1's header layout) and add 48
# to land in ASCII:
echo "latest @ [lit] 9 + c@ [lit] 48 + emit bye" | ./seed-forth
# prints the most-recent word's name length as a digit.  The seed's
# newest word is `0branch`, a seven-character name, so this prints "7".

# Look at the byte dup's xt points to:
echo "' dup c@ emit bye" | ./seed-forth | od -An -tx1
# prints " 48"

# Shadow a primitive:
echo ": dup [lit] 88 emit ; [lit] 1 dup bye" | ./seed-forth
# prints "X"
```

The `48` is the first byte of `dup_code`, `sub rbp, 8`, read out of
memory by the seed itself: `'` pushed dup's xt, and the xt is the
code.  The last command defines a new `dup` at `HERE`; `find` meets
it first on its walk from `LATEST`, and the original 9-byte body is
never reached again.

Now make the reader give up:

```sh
printf '%0300d' 0 | ./seed-forth | wc -c; echo "exit status ${PIPESTATUS[1]}"
# prints "258\nexit status 2"
```

The 300-digit token hit the 256-byte limit: `fatal_token` printed
the 256 bytes it had kept, then `?` and a newline, 258 bytes in all,
and exited with status 2.

## Exercises

1. **★★ Trace.** The dictionary is a singly linked list, newest-to-oldest.  Why
   not oldest-to-newest?  (Hint: `find` checks the most recent
   definition first — shadowing is free.)

2. **★★ Trace.** Why does `find_code` write to `LAST_FOUND` instead of returning
   both the xt *and* the flag byte on the stack?  (Hint: the REPL
   reads `LAST_FOUND` on every hit, in both modes, to test the
   IMMEDIATE bit — but `'` and Forth-level `find` want only the
   xt.  Count instructions in each design.)

3. **★★ Trace.** `read_word` recognises `(` only as a token of its own.  What does
   the seed do with `(a -- b)`, and with `( a -- b)`?  With
   `\comment`?  Predict the output of each, then check.

4. **★★★ Modify.** The seed puts every header directly in front of its code, so
   the xt needs no pointer.  Sketch the alternative: headers in one
   block, each ending in a pointer to (or a `JMP` to) its code
   elsewhere.  What does it cost in bytes for 32 primitives, and in
   instructions per call?  What would it buy?

5. **★★ Trace.** Walk the dictionary backwards by hand starting from `LATEST @`
   (= `0x400617`, the `0branch` entry's link cell).  Follow eight link
   cells.  What's the name at each step?

## Takeaways

- The dictionary is the seed's only data structure: a singly linked
  list of headers searched newest-first, which is what lets a
  redefinition shadow the old word.
- Every header sits directly in front of its word's code, so the xt
  `find` returns, the address just past the name, is the code itself.
- `read_word` leaves `( c-addr u )` for `find`, skips `\` and `( )`
  comments, and hands a token that cannot be used back to the user
  as `token?` rather than guessing.

**Running count: 1,250 of 1,772 bytes read (71%).**  This chapter
added 493, by far the largest share: 196 bytes of lookup, memory and
naming primitives, 199 bytes of token reader and its helpers, and 98
bytes of headers.  Counting the headers read in other chapters, 421
of the seed's bytes, nearly a quarter, are headers: links, flags,
lengths and names.

Every one of those 32 headers was laid by hand.  The library and
the C compiler that Part III loads contain 501 colon definitions
(counting each `:` that starts one), and nobody writes their headers
in hex.  Ch 18 reads the 82 bytes
that do, and `lit_code`, which gets a number into compiled code
through a `CALL` instruction that has no room for one.

Next: Chapter 18 — The Colon Compiler.
