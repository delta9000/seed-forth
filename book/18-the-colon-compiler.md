# Chapter 18 — The Colon Compiler

```text
Missing capability: :, ;, and [lit] are language-level mysteries.
New pattern: : builds a header and flips STATE; bodies use subroutine threading (each word is a call).
Artifact after this chapter: :, ;, [lit], and the lit_code runtime that resolves inline literals.
Proof link: the C compiler's calls mirror this shape — call plus inline operands; same fixup trick.
```

Ch 17's dictionary is fixed at assembly time: 32 hand-laid entries
and no way to add a 33rd.  The library and the compiler need 367
more.  And there is a second gap: a compiled call is `E8` plus a
4-byte displacement, with no field for an argument, so a definition
that needs the number 42 at runtime has nowhere obvious to keep it.
Four pieces of the seed close both gaps.  `colon_code` (`@ 0x2D4`)
parses a name and lays down a header at HERE.  `semicolon_code`
(`@ 0x33B`) appends a `ret` and leaves compile mode.  `lit_code` (`@ 0x419`) is the runtime that compiled
literals call.  `bracket_lit_code` (`@ 0x652`) is the IMMEDIATE
parser behind `[lit]`: it pushes a number in interpret mode, or
emits a `CALL lit_code` plus an 8-byte cell in compile mode.  They
are at lines 263–297, 359–366 and 587–625 of `000-seed.hex0`.

In outline, `:` reads the next token, builds a header for it, and
sets STATE to 1.  From then on the REPL turns each token into a
`CALL` to its xt instead of executing it, until `;` runs, appends a
`ret` byte, and sets STATE back to 0.  The two primitives total 138
bytes (103 for `colon_code`, 35 for `semicolon_code`).  Most of
`colon_code` copies the name; opening a definition is only a pointer
update and a flag write.  How the REPL reacts to STATE is Ch 20, and
the branch primitives that reuse `lit_code`'s inline-cell trick are
Ch 19.

## 1. `colon_code`'s anatomy

`colon_code` is 103 bytes, and most of them build the header:

```hex0 chunk=colon-code
;; ----- colon_code @ 0x2D4 ( -- ) parse name, build header, STATE=1 -----
;; @0x2D4: call read_word (rel32 = 0x259 - 0x2D9 = -128)
E8 80 FF FF FF
48 8B 0C 25 08 30 41 00                   ; mov rcx, [LATEST]
48 8B 14 25 10 30 41 00                   ; mov rdx, [HERE]
48 89 0A                                  ; mov [rdx], rcx       ; entry.link = LATEST
C6 42 08 00                               ; mov byte [rdx+8], 0  ; flags
88 42 09                                  ; mov [rdx+9], al      ; nlen
48 89 C1                                  ; mov rcx, rax
48 C7 C6 00 28 41 00                      ; mov rsi, 0x412800
4C 8D 42 0A                               ; lea r8, [rdx+10]
;; .copy: while (rcx) { *r8++ = *rsi++; rcx-- }
48 85 C9                                  ; test rcx, rcx
74 11                                     ; jz .done_copy
44 8A 0E                                  ; mov r9b, [rsi]
45 88 08                                  ; mov [r8], r9b
48 FF C6                                  ; inc rsi
49 FF C0                                  ; inc r8
48 FF C9                                  ; dec rcx
EB EA                                     ; jmp .copy
;; .done_copy:
48 89 14 25 08 30 41 00                   ; mov [LATEST], rdx    ; LATEST = new entry
48 83 C2 0A                               ; add rdx, 10
48 01 C2                                  ; add rdx, rax
48 89 14 25 10 30 41 00                   ; mov [HERE], rdx       ; HERE += 10 + nlen
48 C7 04 25 00 30 41 00 01 00 00 00       ; mov [STATE], 1
C3

```

It falls into five logical sections:

**(a) Read the name.**  One `call read_word`.  After it returns,
`rax` holds the token length and `[0x412800]` holds the token bytes.
On EOF (`rax == 0`) it builds a header with an empty name; the seed
doesn't guard against that mistake.

**(b) Capture LATEST and HERE.**  `rcx = LATEST` (the address of
the previous entry's link cell, which becomes our new link); `rdx
= HERE` (where the new header will start).

**(c) Write the link, flags, and name-length bytes.**  `mov [rdx],
rcx` stores the 8-byte link cell.  `mov byte [rdx+8], 0` stores the
flags byte (always 0 for user words; only `;` and `[lit]` set
IMMEDIATE, and those are hand-laid).  `mov [rdx+9], al` stores the
name length.  (`al` is the low byte of `rax`, which `read_word` set
to the length.)

**(d) Copy the name bytes.**  A simple while-loop copying `rcx`
bytes from `[0x412800]` to `[rdx+10]`.  Each iteration: read a byte
through `r9b`, write it to `[r8]`, increment both pointers,
decrement the counter.

**(e) Update `LATEST` and `HERE`, flip STATE.**  `LATEST = rdx`
(new entry is the new head of the chain).  `HERE += 10 + nlen`
(the header now owns those bytes; the body starts immediately
after).  `STATE = 1` (we're in compile mode).

## 2. `semicolon_code` in five operations

```hex0 chunk=semicolon-code
;; ----- semicolon_code @ 0x33B ( -- ) IMMEDIATE: append RET, STATE=0 -----
48 8B 04 25 10 30 41 00                   ; mov rax, [HERE]
C6 00 C3                                  ; mov byte [rax], 0xC3
48 FF C0                                  ; inc rax
48 89 04 25 10 30 41 00                   ; mov [HERE], rax
48 C7 04 25 00 30 41 00 00 00 00 00       ; mov [STATE], 0
C3

```

```
mov rax, [HERE]
mov byte [rax], 0xC3   ; write the ret byte at HERE
inc rax                ; advance HERE by 1
mov [HERE], rax
mov [STATE], 0         ; back to interpret mode
ret
```

The new word now ends in `0xC3`, so a later `CALL` to it returns.

## 3. Why `;` is IMMEDIATE at assembly time

If `;` were an ordinary word, the REPL in compile mode would emit a
`CALL` to it and read the next token.  STATE would still be 1, and
the definition would never close.  `;` has to run **at compile
time**, so it has to be IMMEDIATE, and since the seed has no
Forth-level way to set that bit (`immediate` arrives in Ch 10), the
flag is set in its hand-laid header in Ch 17's
`<<dictionary-entries>>`:

```
;; --- ; @ 0x5B0 (xt = 0x5BB) ---  IMMEDIATE
A0 05 40 00 00 00 00 00
01                       ← flags = 01 (IMMEDIATE!)
01                       ← nlen
3B                       ← ";"
E9 7B FD FF FF           ← jmp semicolon_code
```

The REPL (Ch 20) checks this bit before deciding whether to compile
or execute, and on a match it runs the word immediately.  That's how
`;` closes its own definition.

`;` is the only IMMEDIATE word in the 24-entry block.  `[lit]`,
whose entry sits later in the file, is IMMEDIATE for a related
reason: it has to parse the next token *during* compilation.

## 4. `lit_code` and the inline-cell trick

Back to the second gap.  A compiled word is a run of 5-byte `CALL`s,
and a `CALL` carries a target, nothing else.  The seed's answer is
to put the value in the instruction stream itself, right after the
`CALL`, where the CPU would otherwise try to execute it as code:

```
E8 xx xx xx xx          ; CALL lit_code
<8 bytes of V>          ; the inline cell
```

That only works if `lit_code` can find those 8 bytes and then
arrange for execution to resume *after* them.  It has no argument
telling it where they are.  But it has one thing every called
routine has: its return address, which points exactly at the cell.

```hex0 chunk=lit-code
;; ----- lit_code @ 0x419 ( -- v ) reads inline 8-byte cell after CALL site -----
58                                        ; pop rax
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
48 8B 38                                  ; mov rdi, [rax]   ; load inline cell
48 83 C0 08                               ; add rax, 8
50                                        ; push rax
C3                                        ; ret

```

Six instructions plus `ret`, 18 bytes in total.  The `CALL` pushed
the address of the byte *immediately after the CALL*, the first byte
of the inline cell, so `lit_code` starts with `[rsp]` equal to that
address, and pops it as data:

```
pop rax           ; rax = address of inline cell
sub rbp, 8        ; data-stack room
mov [rbp], rdi    ; spill old TOS
mov rdi, [rax]    ; new TOS = the 8-byte cell
add rax, 8        ; rax = address just past the cell
push rax          ; restore as return address, now pointing past the cell
ret               ; return there
```

The key step is `add rax, 8` before pushing back.  Without it,
`ret` would resume at the cell itself and execute the 8 raw bytes
of `V` as machine code.

`lit_code` treats its own return address as a data pointer, then
rewrites it.  This is the seed's first case of instructions and
data interleaved in one byte stream.  `branch_code` and `zbranch_code` (Ch 19) use the
same layout, with a *jump target* in the cell instead of a value to
push.

## 5. `bracket_lit_code`: interpreting and compiling literals

`lit_code` runs at *runtime* and pushes a value the compiler already
wrote.  Something has to write that value: a number in the source,
say `42`, has to become an inline cell.

The seed's answer is `[lit]`.  It's an IMMEDIATE word that parses
the next token as a decimal and either pushes the value (interpret
mode) or compiles a `CALL lit_code + cell` sequence (compile mode).

```hex0 chunk=bracket-lit-code
;; ----- bracket_lit_code @ 0x652 ( -- ) IMMEDIATE -----
;; In interpret mode: parse next token as decimal, push value.
;; In compile mode: parse next token as decimal, compile CALL lit_code + cell.
;; @0x652: call read_word (rel32 = 0x259 - 0x657 = -1022)
E8 02 FC FF FF
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
48 C7 C7 00 28 41 00                      ; mov rdi, 0x412800
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
48 89 C7                                  ; mov rdi, rax
;; @0x671: call parse_decimal_code (rel32 = 0x5FD - 0x676 = -121)
E8 87 FF FF FF
48 8B 7D 00                               ; mov rdi, [rbp]   ; rdi = n (or 0)
48 83 C5 08                               ; add rbp, 8
48 8B 04 25 00 30 41 00                   ; mov rax, [STATE]
48 85 C0                                  ; test rax, rax
75 01                                     ; jnz .Lcompile
C3                                        ; interpret: leave n as TOS
;; .Lcompile:
48 8B 04 25 10 30 41 00                   ; mov rax, [HERE]
C6 00 E8                                  ; mov byte [rax], 0xE8
48 83 C0 05                               ; add rax, 5
48 C7 C2 19 04 40 00                      ; mov rdx, 0x400419 (lit_code body)
48 29 C2                                  ; sub rdx, rax
89 50 FC                                  ; mov [rax-4], edx
48 89 38                                  ; mov [rax], rdi   ; inline 8-byte cell
48 83 C0 08                               ; add rax, 8
48 89 04 25 10 30 41 00                   ; mov [HERE], rax  ; HERE += 13
48 8B 7D 00                               ; mov rdi, [rbp]
48 83 C5 08                               ; add rbp, 8
C3

```

The shape is: call `read_word`, push `(buf-addr, len)` to set up
`parse_decimal_code`'s expected stack, call `parse_decimal_code`,
pop the success flag, branch on STATE.

"Pop" here means *discard*: `[lit]` never tests the flag.  A token
that isn't plain decimal digits (`-5`, `0x41`, `12a`) makes
`parse_decimal_code` return `0 false`, and `[lit]` silently uses
the `0`.  `[lit] -5 [lit] 48 + emit` prints `0`.  Ch 20 has the
details.

In interpret mode (`STATE == 0`) the body just `ret`s with the
parsed value as the new TOS.  Done.

In compile mode (`STATE != 0`) we walk through the literal-
compilation sequence:

```
mov rax, [HERE]                  ; rax = where to write
mov byte [rax], 0xE8             ; opcode for CALL rel32
add rax, 5                       ; rax = address just past the CALL
mov rdx, 0x400419                ; lit_code's address
sub rdx, rax                     ; rdx = rel32 displacement
mov [rax-4], edx                 ; back-patch the displacement
mov [rax], rdi                   ; write the inline cell (8 bytes)
add rax, 8                       ; advance past the cell
mov [HERE], rax                  ; HERE += 13
... pop old TOS, ret
```

Total bytes emitted at HERE: 5 (`CALL lit_code`) + 8 (cell) = 13.

That 13-byte sequence is what `[lit] 42` compiles to when it
appears inside a `:` definition.  At runtime, the `CALL` reaches
`lit_code` with the cell as the return address; `lit_code` reads
the cell, advances past it, returns.  Net effect: `42` ends up on
the data stack.

`[lit]`'s own header sits outside the 24-entry block, at `0x6C0`
next to its code:

```hex0 chunk=bracket-lit-dict
;; --- [lit] @ 0x6C0 (xt = 0x6CF) ---  IMMEDIATE
E7 05 40 00 00 00 00 00                     ; link = 0x4005E7 (0branch)
01                                        ; flags = IMMEDIATE
05                                        ; nlen = 5
5B 6C 69 74 5D                            ; "[lit]"
E9 7E FF FF FF                              ; jmp bracket_lit_code (rel = 0x652 - 0x6D4 = -130)

```

Its `flags` byte is `01` (IMMEDIATE), and its `link` points back to
`0branch`'s entry, the previous word in the linked list.

## 6. Reading a compiled definition

Take `: square dup * ;` as a worked example.

`colon_code` reads `square`, writes a 16-byte header (link, flags
`00`, length `06`, six name bytes), points `LATEST` at it, advances
HERE by 16 and sets STATE to 1.  The REPL, now compiling, reads
`dup`, looks it up, and gets its xt, the `JMP` stub at `0x400491` in `dup`'s header
(Ch 17).  `dup` is not IMMEDIATE (`flags = 00`), so the REPL emits
at HERE:

```
E8 xx xx xx xx          ; CALL dup's xt (5 bytes)
```

HERE advances by 5.  At runtime this `CALL` lands on the stub,
which `JMP`s on to `dup_code`.

Then `*`: the same routine, 5 more bytes for a `CALL` to `*`'s xt.

Then `;`, which is IMMEDIATE.  The REPL runs `semicolon_code` instead of
compiling a call to it.  `semicolon_code` writes `C3` at HERE
(advance by 1), then sets STATE to 0.

Total body size for `square`: `5 + 5 + 1 = 11` bytes.  Total entry
size: `10 + 6 + 11 = 27` bytes.

Try it for `: five [lit] 5 ;` and verify the body is `13 + 1 = 14`
bytes, for a total entry of `10 + 4 + 14 = 28`.  `[lit]` is
IMMEDIATE, so no `CALL` to `[lit]` itself is compiled; it runs at
compile time and emits only a `CALL lit_code` plus the 8-byte `5`
cell, 13 bytes.  The last command in Try it measures this.

## Try it

```sh
./build.sh

echo ": square dup * ; [lit] 7 square [lit] 48 + emit bye" | ./seed-forth
# 7*7 = 49; 49 + 48 = 97 = ASCII 'a'.  Prints "a".
# (To print the digit '1' instead, drop `[lit] 48 +`: 49 is
# already ASCII '1'.)

echo ": five [lit] 5 ; five [lit] 48 + emit bye" | ./seed-forth
# 5 + 48 = 53 = '5'. prints "5".

echo ": ab [lit] 65 emit [lit] 66 emit ; ab ab bye" | ./seed-forth
# defines ab to emit 'AB', then calls it twice. prints "ABAB".
```

Try defining a word that calls another word you just defined:

```sh
echo ": A [lit] 65 emit ;  : AAA A A A ;  AAA bye" | ./seed-forth
# prints "AAA"
echo "here : five [lit] 5 ; here swap dup nand + [lit] 1 + [lit] 48 + emit bye" | ./seed-forth
# prints "L"
```

The last line has the seed measure its own compiler.  It pushes
`HERE`, defines `five`, pushes `HERE` again, and subtracts the two
using only primitives (`dup nand` is bitwise not, and `not + 1` is
negation).  The difference is 28, and `28 + 48` is 76, ASCII `L`:
exactly the 10-byte header, 4-byte name and 14-byte body from §6,
written into memory by `colon_code`, `bracket_lit_code` and
`semicolon_code` while you watched.

## Exercises

1. **★★ Trace.** The header built by `:` is exactly `10 + nlen` bytes.  Compute
   it for `: square`.  Compute it for a 240-character name.  Does
   the name-length byte limit you to 255?  What would happen at
   length 256?  Trace which instruction in `colon_code` truncates.

2. **★ Trace.** `;`'s appended `ret` (`C3`) is the only thing that ends a colon
   definition.  Why is `ret` enough?  (Hint: was the colon
   definition *entered* via `CALL` or via `JMP`?)

3. **★★ Trace.** `lit_code` advances the return address by 8.  Trace what would
   happen if you forgot to advance (`add rax, 8` deleted): what
   does `ret` execute next?  Now what if you advanced by 7 or 9?

4. **★★ Extend.** Write a hypothetical `2lit_code` that reads 16 inline bytes and
   pushes two cells.  Sketch how the compile-mode REPL would emit
   calls to it from a source like `[2lit] 42 100`.

5. **★★★ Modify.** Modify a copy of `000-seed.hex0` so that `:` also accepts an
   "IMMEDIATE" suffix at parse time (e.g., `: foo immediate ...`),
   setting the flags byte to `01` instead of `00`.  Where in
   `colon_code` does the change go?  How many bytes?

## Takeaways

- `:` and `;` total 138 bytes, most of it spent copying the name;
  opening and closing a definition is a STATE write plus, for `;`,
  one `ret` byte.
- `;` and `[lit]` carry `flags = 01` in their hand-laid headers
  because both must run during compilation instead of being
  compiled.
- `lit_code` reads an 8-byte cell placed right after its `CALL` and
  returns past it, the inline-cell convention that `branch` and
  `0branch` reuse in Ch 19.

**Running count: 1,734 of 2,040 bytes read (85%).**  This chapter
added 286: `:` and `;` (138), `lit_code` (18), and `[lit]`'s
110-byte body and 20-byte entry.

`lit_code` returns to an address it computed: the cell's address
plus 8.  Return instead to the address *stored in* the cell, and a
`CALL` becomes a jump.  Ch 19 reads the two primitives that do
exactly that, 34 bytes that carry every `if,` and every loop in the
library and the compiler.

Next: Chapter 19 — Branches and Inline Cells.
