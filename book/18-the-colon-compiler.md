# Chapter 18 — The Colon Compiler

```text
Missing capability: :, ;, and [lit] are language-level mysteries.
New pattern: : builds a header and flips STATE; bodies use subroutine threading (each word is a call).
Artifact after this chapter: :, ;, [lit], and the lit_code runtime that resolves inline literals.
Proof link: the C compiler's calls mirror this shape — call plus inline operands; same fixup trick.
```

Four pieces of the seed turn the dictionary from a read-only table
into a Forth that can *define new words*: `colon_code` (`@ 0x2D4`)
parses a name and lays down a header at HERE; `semicolon_code`
(`@ 0x33B`) appends a `ret` and exits compile mode; `lit_code`
(`@ 0x419`) is the inline-cell runtime that compiled `[lit]`s call;
and `bracket_lit_code` (`@ 0x652`) is the immediate parser that
emits those `CALL lit_code` + 8-byte cell sequences in compile mode
or pushes the number directly in interpret mode.  Open
`000-seed.hex0` to lines 263–297, 359–366, and 587–625 to read along.

By the end of the chapter you'll be able to read each of those four
bodies byte for byte, explain why `;`'s IMMEDIATE flag is set in
its hand-laid dictionary header rather than at runtime, and trace
the inline-literal convention that `lit_code` and the branch
primitives share.  The REPL's side of the story (how `:` flips
STATE and `find_code` switches between interpret and compile
behaviour) is Ch 20; the branch primitives that share `lit_code`'s
inline-slot trick are Ch 19.

---

`:` and `;` together are how Forth defines new words.  In interpret
mode, a `:` reads the next token, builds a dictionary header for
it, and flips the seed into compile mode.  Every subsequent token
gets *compiled* (turned into a `CALL` to its xt, plus inline cells
where needed) rather than executed.  Then `;` runs — it appends a
`ret` byte and flips STATE back to 0.

The whole compiler is two primitives, 138 bytes of hex between
them (103 for `colon_code`, 35 for `semicolon_code`).  Most of
`colon_code` is parsing the name and copying it into the header; the
actual "open a definition" is a flag flip and a pointer update.
Most of `semicolon_code` is the *same* flag flip in reverse, plus
the appended `ret`.

`lit_code` and `bracket_lit_code` are the supporting cast: how
literals reach the data stack when the source has nothing but
whitespace-separated tokens.

## 1. `colon_code`'s anatomy

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

Five logical sections:

**(a) Read the name.**  One `call read_word`.  After it returns,
`rax` holds the token length and `[0x412800]` holds the token bytes.
If `rax == 0` (EOF), the rest of the routine will store a zero-byte
header — broken, but the seed accepts it because users don't write
`:` followed by EOF unless they made a mistake.

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

That last byte before `ret` is the whole reason for the chapter:
the REPL (Ch 20) loops on STATE, and the next time around the loop
it will see STATE=1 and switch to compile mode — emitting `CALL`s
instead of executing.

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

That's the entire compiler-closing routine.  The body being
compiled now ends in a `0xC3` — `ret` — so when something later
`CALL`s the new word, the `ret` returns to the caller and execution
continues normally.

## 3. Why `;` is IMMEDIATE at assembly time

`;` cannot be compiled like an ordinary word.  Consider what would
happen if it weren't IMMEDIATE: the REPL is in compile mode (STATE
= 1), and the next token is `;`.  The compile-mode handler would
emit a `CALL semicolon_code` instruction at HERE — and then loop
back to read the next token.  STATE is still 1; the body being
compiled never gets closed.

For `;` to *close the current definition*, it has to run **at
compile time**, not at runtime.  That means it has to be IMMEDIATE.
And since the seed has no Forth-level way to *set* the IMMEDIATE
bit (that comes in `010-lib.fth`'s `immediate` word, Ch 10), the
flag has to be set in the hand-laid dictionary header.

Look back at Ch 17's `<<dictionary-entries>>` chunk and find the
`;` entry:

```
;; --- ; @ 0x5B0 (xt = 0x5BB) ---  IMMEDIATE
A0 05 40 00 00 00 00 00
01                       ← flags = 01 (IMMEDIATE!)
01                       ← nlen
3B                       ← ";"
E9 7B FD FF FF           ← jmp semicolon_code
```

`flags = 01`.  The REPL's compile-mode handler (Ch 20) checks this
bit before deciding whether to compile or execute, and on a match
it runs the word immediately.  That's how `;` closes its own
definition.

`;` is the *only* IMMEDIATE word among the original 24 in the
dictionary block.  `[lit]` (added later) is also IMMEDIATE — same
reason: it has to parse the next token *during* compilation.

## 4. `lit_code` and the inline-cell trick

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

Six instructions plus `ret` — 18 bytes total.  Read it once and the
convention will lock in for the rest of Part II.

When the compiler wants to push a constant `V` at runtime, it emits:

```
E8 xx xx xx xx          ; CALL lit_code
<8 bytes of V>          ; the inline cell, sitting where execution would otherwise continue
```

At runtime, the `CALL` pushes the address of the byte *immediately
after the CALL* — which is the first byte of the inline cell — onto
the return stack as the return address.  `lit_code` is now executing
with `[rsp]` equal to that address.

```
pop rax           ; rax = address of inline cell
sub rbp, 8        ; data-stack room
mov [rbp], rdi    ; spill old TOS
mov rdi, [rax]    ; new TOS = the 8-byte cell
add rax, 8        ; rax = address just past the cell
push rax          ; restore as return address, now pointing past the cell
ret               ; return there
```

The trick is the `add rax, 8` before pushing back.  Without it,
`ret` would resume at the address of the cell — i.e., execute the
8 raw bytes of `V` as machine code, which would be gibberish or
worse.

This is the seed's first instance of *executable instructions and
data interleaved in the same byte stream*.  The same pattern recurs
in `branch_code` and `zbranch_code` (Ch 19), where the inline cell
is a *jump target* instead of a value to push.

```
   (V) (V)
   ( o.o )   "the function reads its own return address as a
   /\/\/\     data pointer.  the return stack is a data stack
            now.  briefly.  for science."
```

## 5. `bracket_lit_code` — interpreting and compiling literals

`lit_code` runs at *runtime* and pushes a value the compiler already
wrote.  But who writes that value?  How does a number written in
source — say, `42` — become an inline cell?

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

```hex0 chunk=bracket-lit-dict
;; --- [lit] @ 0x6C0 (xt = 0x6CF) ---  IMMEDIATE
E7 05 40 00 00 00 00 00                     ; link = 0x4005E7 (0branch)
01                                        ; flags = IMMEDIATE
05                                        ; nlen = 5
5B 6C 69 74 5D                            ; "[lit]"
E9 7E FF FF FF                              ; jmp bracket_lit_code (rel = 0x652 - 0x6D4 = -130)

```

The `[lit]` dictionary entry, with `flags = 01` (IMMEDIATE).  Its
`link` points back to `0branch`'s entry (the previous word in the
linked list).

## 6. Reading a compiled definition

Take `: square dup * ;` as a worked example.

When the REPL processes `:`, it calls `colon_code`, which:
1. Reads `square` via `read_word`.
2. Captures `[LATEST]` and `[HERE]`.
3. Writes the link cell, flags `00`, name length `06`, name bytes.
4. Updates `LATEST` to point at the new entry.
5. Advances HERE by `10 + 6 = 16`.
6. Sets STATE to 1.

Then the REPL is in compile mode.  It reads `dup`, looks it up,
gets the xt for `dup_code`, sees that `dup` is not IMMEDIATE
(`flags = 00`), and emits at HERE:

```
E8 xx xx xx xx          ; CALL dup_code (5 bytes)
```

HERE advances by 5.

Then `*` — same routine, 5 more bytes for `CALL star_code`.

Then `;` — IMMEDIATE.  The REPL runs `semicolon_code` instead of
compiling a call to it.  `semicolon_code` writes `C3` at HERE
(advance by 1), then sets STATE to 0.

Total body size for `square`: `5 + 5 + 1 = 11` bytes.  Total entry
size: `10 + 6 + 11 = 27` bytes.

Try it for `: five [lit] 5 ;` and verify the body is `5 + 13 + 1 =
19` bytes.  (The `[lit] 5` part compiles to a `CALL lit_code` +
8-byte `5` cell — 13 bytes total.)

## Try it

```sh
./build.sh

echo ": square dup * ; [lit] 7 square [lit] 48 + emit bye" | ./seed-forth
# 7*7 = 49; 49 + 48 = 97 = ASCII 'a'.  Prints "a".
# (If you wanted to see the digit '1', the second `[lit] 48` would
# be redundant: 49 itself already is ASCII '1'.)

echo ": five [lit] 5 ; five [lit] 48 + emit bye" | ./seed-forth
# 5 + 48 = 53 = '5'. prints "5".

echo ": ab [lit] 65 emit [lit] 66 emit ; ab ab bye" | ./seed-forth
# defines ab to emit 'AB', then calls it twice. prints "ABAB".
```

Try defining a word that calls another word you just defined:

```sh
echo ": A [lit] 65 emit ;  : AAA A A A ;  AAA bye" | ./seed-forth
# prints "AAA"
```

## Exercises

1. **★★ Trace.** The header built by `:` is exactly `10 + nlen` bytes.  Compute
   it for `: square`.  Compute it for a 240-character name.  Does
   the name-length byte limit you to 255?  What would happen at
   length 256?  Trace which instruction in `colon_code` truncates.

2. **★ Trace.** `;`'s appended `ret` (`C3`) is the only thing that ends a colon
   definition.  Why is `ret` enough?  (Hint: how was the colon
   definition *entered* — via `CALL` or via `JMP`?)

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

- `:` and `;` are 130 bytes of hex between them.  Most of `:` is
  parsing and copying the name; the actual "open / close a
  compilation unit" is one flag flip and one byte of `ret`.
- `;` is IMMEDIATE at assembly time, with `flags = 01` in its
  dictionary entry — the *only* original IMMEDIATE; `[lit]` is the
  one other IMMEDIATE the seed adds, for the same reason: it must
  run during compilation.
- `lit_code`'s inline-cell trick is the model for `branch_code` and
  `zbranch_code` in the next chapter.  Inline data, executable as
  no-ops only because the primitive arranges to step over them.

Next: Chapter 19 — Branches and Inline Cells.
