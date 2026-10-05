# Chapter 18 — The Colon Compiler

```text
Missing capability: :, ;, and [lit] are language-level mysteries.
New pattern: : builds a header and flips STATE; bodies use subroutine threading (each word is a call).
Artifact after this chapter: :, ;, [lit], and the lit_code runtime that resolves inline literals.
Proof link: the C compiler's calls mirror this shape — call plus inline operands; same fixup trick.
```

Ch 17's dictionary is fixed at assembly time: 32 hand-laid entries
and no way to add a 33rd.  The library and the compiler need 1,392
colon definitions, and more entries still for their variables and
constants.  And there is a second gap: a compiled call is `E8` plus a
4-byte displacement, with no field for an argument, so a definition
that needs the number 42 at runtime has nowhere obvious to keep it.
Four pieces of the seed close both gaps.  `colon_code` (`@ 0x4ED`)
parses a name and lays down a header at HERE.  `semicolon_code`
(`@ 0x54A`) appends a `ret` and leaves compile mode.  `lit_code`
(`@ 0x5A0`) is the runtime that compiled literals call.
`bracket_lit_code` (`@ 0x5C1`) is the IMMEDIATE parser behind
`[lit]`: it pushes a number in interpret mode, or emits a
`CALL lit_code` plus an 8-byte cell in compile mode.  Between `;`
and `lit` sits `compile_call`, the unnamed helper that lays down one
`CALL` instruction, for `[lit]` here and for the REPL in Ch 20.  All
of it is lines 515–600 of `000-seed.hex0`.

In outline, `:` reads the next token, builds a header for it, and
sets STATE to 1.  From then on the REPL turns each token into a
`CALL` to its xt instead of executing it, until `;` runs, appends a
`ret` byte, and sets STATE back to 0.  The two primitives' code
totals 117 bytes (82 for `colon_code`, 35 for `semicolon_code`).
Most of `colon_code` writes the header's fields; the name itself is
copied by one instruction, and opening a definition is only a
pointer update and a flag write.  How the REPL reacts to STATE is Ch 20, and
the branch primitives that reuse `lit_code`'s inline-cell trick are
Ch 19.

## 1. `colon_code`'s anatomy

`colon_code` is 82 bytes, and most of them build the header:

```hex0 chunk=colon
;; --- : @ 0x4E2 --- header
CD 04 40 00 00 00 00 00                   ; link  = 0x4004CD (')
00                                        ; flags = 0
01                                        ; nlen  = 1
3A                                        ; name  = ":"
;; ----- colon_code @ 0x4ED  ( -- ) read a name, lay down its header at HERE, STATE = 1 -----
E8 CF FE FF FF                            ; call read_word  (rel32 = 0x3C1 - 0x4F2) ; ( -- c-addr u )
48 8B 0C 25 08 30 41 00                   ; mov rcx, [LATEST]
48 8B 14 25 10 30 41 00                   ; mov rdx, [HERE]    ; rdx = the new entry
48 89 0A                                  ; mov [rdx], rcx     ; link  = old LATEST
C6 42 08 00                               ; mov byte [rdx+8], 0 ; flags = 0
40 88 7A 09                               ; mov [rdx+9], dil   ; nlen  = u
48 89 14 25 08 30 41 00                   ; mov [LATEST], rdx  ; the new entry is the newest
48 89 F9                                  ; mov rcx, rdi       ; count = u
48 8B 75 00                               ; mov rsi, [rbp]     ; from = c-addr
48 8D 7A 0A                               ; lea rdi, [rdx+10]  ; to = the name field
F3 A4                                     ; rep movsb          ; copy the name; rdi ends just past it
48 89 3C 25 10 30 41 00                   ; mov [HERE], rdi    ; HERE = entry + 10 + u
48 8B 7D 08                               ; mov rdi, [rbp+8]   ; drop c-addr and u
48 83 C5 10                               ; add rbp, 16
48 C7 04 25 00 30 41 00 01 00 00 00       ; mov qword [STATE], 1
C3                                        ; ret

```

It falls into five logical sections:

**(a) Read the name.**  One `call read_word`.  After it returns,
the data stack holds `( c-addr u )`: `rdi` is the length and
`0x412800` holds the token bytes.  On EOF (`u == 0`) it builds a
header with an empty name; the seed doesn't guard against that
mistake.

**(b) Capture LATEST and HERE.**  `rcx = LATEST` (the address of
the previous entry's link cell, which becomes our new link); `rdx
= HERE` (where the new header will start).

**(c) Write the link, flags, and name-length bytes.**  `mov [rdx],
rcx` stores the 8-byte link cell.  `mov byte [rdx+8], 0` stores the
flags byte (always 0 for user words; only `;` and `[lit]` set
IMMEDIATE, and those are hand-laid).  `mov [rdx+9], dil` stores the
name length (`dil` is the low byte of `rdi`, the length
`read_word` left on top of the stack).  Then `LATEST = rdx`: the
new entry is the new head of the chain.

**(d) Copy the name bytes.**  `rep movsb` copies `rcx` bytes from
`[rsi]` to `[rdi]`, advancing both pointers, so the three
instructions before it load the count (`u`), the source (the
`c-addr` under TOS) and the destination (`rdx+10`, the name field).
The copy runs forward because the direction flag is clear: Linux
starts every process with it clear, and nothing in the seed sets it.
When `rep movsb` finishes, `rdi` points just past the name.

**(e) Update HERE, drop the token, flip STATE.**  That end-of-name
address is where the body starts, so it becomes `HERE`: the header
now owns `10 + nlen` bytes.  `mov rdi, [rbp+8]; add rbp, 16` drops
`c-addr` and `u` in one go, restoring the TOS from before the call.
`STATE = 1` (we're in compile mode).

## 2. `semicolon_code` in five operations

```hex0 chunk=semicolon
;; --- ; @ 0x53F --- header  IMMEDIATE
E2 04 40 00 00 00 00 00                   ; link  = 0x4004E2 (:)
01                                        ; flags = 1 (IMMEDIATE)
01                                        ; nlen  = 1
3B                                        ; name  = ";"
;; ----- semicolon_code @ 0x54A  ( -- ) IMMEDIATE: append ret, STATE = 0 -----
48 8B 04 25 10 30 41 00                   ; mov rax, [HERE]
C6 00 C3                                  ; mov byte [rax], 0xC3 ; the ret opcode
48 FF C0                                  ; inc rax
48 89 04 25 10 30 41 00                   ; mov [HERE], rax
48 C7 04 25 00 30 41 00 00 00 00 00       ; mov qword [STATE], 0
C3                                        ; ret

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
flag is set in its hand-laid header, the four lines above
`semicolon_code` in the chunk you just read:

```
;; --- ; @ 0x53F --- header  IMMEDIATE
E2 04 40 00 00 00 00 00  ← link  = 0x4004E2 (:)
01                       ← flags = 01 (IMMEDIATE!)
01                       ← nlen
3B                       ← ";"
```

The REPL (Ch 20) checks this bit before deciding whether to compile
or execute, and on a match it runs the word immediately.  That's how
`;` closes its own definition.

`;` is one of the seed's two IMMEDIATE words.  `[lit]` is the
other, for a related reason: it has to parse the next token
*during* compilation.

## 4. `compile_call`: one `CALL`, laid down at HERE

In compile mode the REPL turns each word into a `CALL` to its xt,
and `[lit]` below needs to compile a `CALL` to `lit_code`.  Both use
this helper:

```hex0 chunk=compile-call
;; ----- compile_call @ 0x56D  ( xt -- ) lay down CALL xt (E8 rel32) at HERE -----
;; Not a dictionary word: the REPL's compile path and [lit] share it.
48 8B 04 25 10 30 41 00                   ; mov rax, [HERE]
C6 00 E8                                  ; mov byte [rax], 0xE8 ; the CALL opcode
48 83 C0 05                               ; add rax, 5         ; rax = address after the CALL
48 29 C7                                  ; sub rdi, rax       ; rel32 = xt - (HERE + 5)
89 78 FC                                  ; mov [rax-4], edi
48 89 04 25 10 30 41 00                   ; mov [HERE], rax    ; HERE += 5
48 8B 7D 00                               ; mov rdi, [rbp]
48 83 C5 08                               ; add rbp, 8
C3                                        ; ret

```

A `CALL rel32` is five bytes: `E8` and a displacement measured from
the end of the instruction.  So the helper writes `E8` at HERE,
advances `rax` to HERE + 5, computes `xt - rax` in `rdi` and stores
its low 32 bits into the four bytes before `rax`.  Then HERE moves
past the instruction and the xt is dropped.  It is the same
arithmetic as Ch 10's `call,`, `rel32 = target - (HERE + 5)`,
done once in hex so the seed's two compilers share it.

## 5. `lit_code` and the inline-cell trick

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

```hex0 chunk=lit
;; --- lit @ 0x593 --- header
3F 05 40 00 00 00 00 00                   ; link  = 0x40053F (;)
00                                        ; flags = 0
03                                        ; nlen  = 3
6C 69 74                                  ; name  = "lit"
;; ----- lit_code @ 0x5A0  ( -- v ) push the 8-byte cell after the CALL, skip it -----
58                                        ; pop rax            ; rax = return address = the cell
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
48 8B 38                                  ; mov rdi, [rax]     ; TOS = the cell
48 83 C0 08                               ; add rax, 8         ; step past it
50                                        ; push rax
C3                                        ; ret                ; resume after the cell

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

## 6. `bracket_lit_code`: interpreting and compiling literals

`lit_code` runs at *runtime* and pushes a value the compiler already
wrote.  Something has to write that value: a number in the source,
say `42`, has to become an inline cell.

The seed's answer is `[lit]`.  It's an IMMEDIATE word that parses
the next token as a decimal and either pushes the value (interpret
mode) or compiles a `CALL lit_code + cell` sequence (compile mode).

```hex0 chunk=bracket-lit
;; --- [lit] @ 0x5B2 --- header  IMMEDIATE
93 05 40 00 00 00 00 00                   ; link  = 0x400593 (lit)
01                                        ; flags = 1 (IMMEDIATE)
05                                        ; nlen  = 5
5B 6C 69 74 5D                            ; name  = "[lit]"
;; ----- bracket_lit_code @ 0x5C1  ( -- n ) IMMEDIATE: read a decimal number -----
;; Interpret mode: leave n on the stack.  Compile mode: compile CALL lit
;; and the cell n.  A token that is not a decimal number is fatal.
E8 FB FD FF FF                            ; call read_word  (rel32 = 0x3C1 - 0x5C6) ; ( -- c-addr u )
E8 79 00 00 00                            ; call parse_decimal_code  (rel32 = 0x644 - 0x5CB) ; ( c-addr u -- n flag )
48 85 FF                                  ; test rdi, rdi
0F 84 A3 FE FF FF                         ; jz fatal_token  (rel32 = 0x477 - 0x5D4) ; not a number: report and exit
48 8B 7D 00                               ; mov rdi, [rbp]
48 83 C5 08                               ; add rbp, 8         ; drop the flag: ( n )
48 8B 04 25 00 30 41 00                   ; mov rax, [STATE]
48 85 C0                                  ; test rax, rax
75 01                                     ; jnz .compile  (rel8 = 0x5EA - 0x5E9)
C3                                        ; ret                ; interpret: n stays on the stack
;; .compile:
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi
BF A0 05 40 00                            ; mov edi, 0x4005A0 ; ( n lit-xt )
E8 71 FF FF FF                            ; call compile_call  (rel32 = 0x56D - 0x5FC) ; ( n ) CALL lit
E9 82 FD FF FF                            ; jmp comma_code  (rel32 = 0x383 - 0x601) ; ( ) the cell n, tail call

```

The shape is: call `read_word`, which leaves `( c-addr u )`, exactly
the stack `parse_decimal_code` (Ch 20) expects; call it; test the
flag it returns; drop the flag; branch on STATE.

**A token that is not a number is fatal.**  `parse_decimal_code`
accepts only unsigned decimal digits, so `-5`, `0x41` and `12a` all
come back with a false flag, and so does an empty token at end of
input.  `[lit]` then jumps to `fatal_token` (Ch 17): the seed prints
the token followed by `?` and exits with status 2.  A literal the
seed cannot read never becomes a silent 0 in compiled code.

In interpret mode (`STATE == 0`) the body just `ret`s with the
parsed value as the new TOS.  Done.

In compile mode (`STATE != 0`) the seed compiles a literal with the
two tools it already has:

```
sub rbp, 8; mov [rbp], rdi       ; push a copy of n: ( n n )
mov edi, 0x4005A0                ; replace it with lit's xt: ( n lit-xt )
call compile_call                ; ( n )  CALL lit_code at HERE, 5 bytes
jmp comma_code                   ; ( )    the cell n at HERE, 8 bytes
```

The last step is a tail call into `,` (Ch 17): its `ret` returns
straight to whoever called `[lit]`.  `0x4005A0` is `lit_code`'s
address, typed into the instruction by hand like every other
absolute address in the seed.

Total bytes emitted at HERE: 5 (`CALL lit_code`) + 8 (cell) = 13.

That 13-byte sequence is what `[lit] 42` compiles to when it
appears inside a `:` definition.  At runtime, the `CALL` reaches
`lit_code` with the cell as the return address; `lit_code` reads
the cell, advances past it, returns.  Net effect: `42` ends up on
the data stack.

`[lit]`'s header, directly above its code, has `flags = 01`
(IMMEDIATE), and its `link` points back to `lit`'s header, the
previous word in the linked list.

## 7. Reading a compiled definition

Take `: square dup * ;` as a worked example.

`colon_code` reads `square`, writes a 16-byte header (link, flags
`00`, length `06`, six name bytes), points `LATEST` at it, advances
HERE by 16 and sets STATE to 1.  The REPL, now compiling, reads
`dup`, looks it up, and gets its xt, `0x4000C7`, the first byte of
`dup_code` (Ch 17).  `dup` is not IMMEDIATE (`flags = 00`), so the
REPL has `compile_call` emit at HERE:

```
E8 xx xx xx xx          ; CALL dup's xt (5 bytes)
```

HERE advances by 5.  At runtime this `CALL` lands on `dup_code`
itself.

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
cell, 13 bytes.  The last command in Try it measures this.  (`[lit] 5`, not `5`:
the seed has no other way to read a number, Ch 20.)

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

A literal the seed cannot read stops everything:

```sh
echo ": t [lit] 0x41 emit ; t" | ./seed-forth || echo "exit status $?"
# prints "0x41?\nexit status 2"
```

`t` is never finished and never run: `[lit]` printed the token it
rejected and the process ended there, with status 2.

## Exercises

1. **★★ Trace.** The header built by `:` is exactly `10 + nlen` bytes.  Compute
   it for `: square`.  Compute it for a 255-character name.  What
   stops a 256-character name, and where?  If it got through, what
   would `mov [rdx+9], dil` store, and what would `find` then do
   with the entry?

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

- `:` and `;` are 117 bytes of code; `:` writes a header and copies
  the name with one `rep movsb`, and opening and closing a
  definition is a STATE write plus, for `;`, one `ret` byte.
- `;` and `[lit]` carry `flags = 01` in their hand-laid headers
  because both must run during compilation instead of being
  compiled.
- `lit_code` reads an 8-byte cell placed right after its `CALL` and
  returns past it, the inline-cell convention that `branch` and
  `0branch` reuse in Ch 19; `[lit]` compiles that pair with
  `compile_call` and `,`, and refuses any token that is not a
  decimal number.

**Running count: 1,537 of 1,772 bytes read (87%).**  This chapter
added 287: `:` and `;` with their headers (93 and 46),
`compile_call` (38), `lit` (31) and `[lit]` (79).

`lit_code` returns to an address it computed: the cell's address
plus 8.  Return instead to the address *stored in* the cell, and a
`CALL` becomes a jump.  Ch 19 reads the two primitives that do
exactly that, 34 bytes that carry every `if,` and every loop in the
library and the compiler.

Next: Chapter 19 — Branches and Inline Cells.
