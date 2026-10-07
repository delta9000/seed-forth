# Chapter 20 — The Number Parser and REPL

```text
Missing capability: the seed has no way to enter numbers or run user input.
New pattern: an 83-byte loop — read token → find → miss echoes the token with ? or dispatch on IMMEDIATE+STATE (execute, or compile a CALL) → loop or bye.
Artifact after this chapter: the seed is now a self-contained host that can load and run the C compiler.
Proof link: this chapter is the bridge into Part III — the host the C compiler sits on top of.
```

The seed has no shell, no command-line flags, no `include` and no
file loader.  Part III builds a working M2-Planet with it anyway,
using one pipe: the library and the compiler exactly as they are
written, comments and all, then M2-Planet's C source, all into
`./seed-forth`'s stdin.  Something reads that stream, compiles
13,225 lines of Forth (`010-lib.fth` through `120-cc-main.fth`) into
1,528 colon definitions, and then runs the compiler it just built on
the rest of the input.  That something is
an 83-byte loop at `0x699` (lines 664–689), the last routine in the
file.  It is the seed's loader, linker and command interpreter at
once, and it is the last code in `000-seed.hex0` you haven't read.

The REPL reads a token, looks it up, and either executes it
(interpret mode) or compiles a call to it (compile mode).  A miss
prints the token and `?`, and EOF jumps to `bye_code`.  The dispatch
tests the IMMEDIATE flag first and STATE second.  Its companion
`parse_decimal_code` (`@ 0x644`, lines 633–662) turns a token like
`"42"` into a number, with the contract `( c-addr u -- n true | 0
false )`; empty input or any byte outside `'0'..'9'`, a leading `-`
included, makes it fail.  The REPL never calls it: numbers enter
only through `[lit]` (Ch 18), a choice §3 examines.

## 1. `parse_decimal_code` ( c-addr u -- n true | 0 false )

The parser is one digit loop with a success tail and a failure tail:

```hex0 chunk=parse-decimal
;; ----- parse_decimal_code @ 0x644  ( c-addr u -- n true | 0 false ) -----
;; Not a dictionary word ([lit] calls it).  Unsigned decimal only: an
;; empty token or any byte outside '0'..'9' fails.  n = n*10 + digit.
48 8B 75 00                               ; mov rsi, [rbp]     ; rsi = c-addr
48 83 C5 08                               ; add rbp, 8
48 85 FF                                  ; test rdi, rdi
74 38                                     ; jz .fail  (rel8 = 0x689 - 0x651)      ; empty token
48 31 C0                                  ; xor rax, rax       ; n = 0
48 89 F9                                  ; mov rcx, rdi       ; rcx = bytes left
;; .loop:
48 0F B6 16                               ; movzx rdx, byte [rsi]
48 83 EA 30                               ; sub rdx, 0x30      ; - '0'
78 28                                     ; js .fail  (rel8 = 0x689 - 0x661)      ; below '0'
48 83 FA 09                               ; cmp rdx, 9
7F 22                                     ; jg .fail  (rel8 = 0x689 - 0x667)      ; above '9'
48 8D 04 80                               ; lea rax, [rax+rax*4] ; n * 5
48 01 C0                                  ; add rax, rax       ; n * 10
48 01 D0                                  ; add rax, rdx       ; + digit
48 FF C6                                  ; inc rsi
48 FF C9                                  ; dec rcx
75 DE                                     ; jnz .loop  (rel8 = 0x657 - 0x679)
48 83 ED 08                               ; sub rbp, 8
48 89 45 00                               ; mov [rbp], rax     ; push n
48 C7 C7 FF FF FF FF                      ; mov rdi, -1        ; true
C3                                        ; ret
;; .fail:
48 83 ED 08                               ; sub rbp, 8
48 C7 45 00 00 00 00 00                   ; mov qword [rbp], 0 ; push 0
48 31 FF                                  ; xor rdi, rdi       ; false
C3                                        ; ret

```

Setup:
- TOS (`rdi`) holds the byte count `u`.
- Under-TOS (`[rbp]`) holds the buffer address `c-addr`.
- We pop the under-TOS into `rsi` and use `rcx` as the loop counter.
- `rax` accumulates the result.

Loop body — for each byte:
1. Load it (`movzx rdx, byte [rsi]`).
2. Subtract `'0'` (= `0x30`).
3. If the result is *negative* (signed test `js`), the byte was
   less than `'0'`; fail.
4. If the result is *greater than 9*, the byte was greater than
   `'9'`; fail.
5. Otherwise multiply the accumulator by 10 (`lea rax, [rax +
   rax*4]; add rax, rax`) and add the digit.
6. Advance the buffer pointer; decrement the count.
7. If count is non-zero, loop.

The `lea` computes `rax*5` and the `add` doubles it: a multiply by
10 in two instructions and no temporary register.  So each step is `n = n*10 + digit`: Horner's rule, most
significant digit first.  `"42"` becomes `0*10 + 4 = 4`, then
`4*10 + 2 = 42`.  There is no overflow check: a
value of 2^64 or more silently wraps modulo 2^64.

Success path:
- Push the parsed value `n` onto the data stack (it goes into
  the new under-TOS slot via `mov [rbp], rax`).
- Set `rdi` to `-1` (Forth-canonical true).

Failure path:
- Push the cell `0` onto the data stack.
- Set `rdi` to `0` (Forth-canonical false).

Its one caller, `[lit]` (Ch 18), tests the flag and treats false as
fatal, so the `0` is never used as a value.

Two things to flag.

**This is a one-shot parser, not a partial parser.**  If any byte
fails the range check, the *whole token* fails.

**No sign handling.**  `-42` fails at the `-` byte (`0x2D < 0x30`,
so `js` triggers).  The C compiler in Part III treats negation as a
unary operator, so the restriction is invisible to it.

## 2. The REPL loop

The loop that drives everything is 83 bytes:

```hex0 chunk=repl
;; ----- repl @ 0x699  read a token, find it, run or compile it; loop -----
;; Not a dictionary word.  _start jumps here; it never returns.
E8 23 FD FF FF                            ; call read_word  (rel32 = 0x3C1 - 0x69E) ; ( -- c-addr u )
48 85 FF                                  ; test rdi, rdi
0F 84 93 FB FF FF                         ; jz bye_code  (rel32 = 0x23A - 0x6A7)  ; u = 0: end of input, exit(0)
E8 57 FC FF FF                            ; call find_code  (rel32 = 0x303 - 0x6AC) ; ( c-addr u -- xt | 0 )
48 85 FF                                  ; test rdi, rdi
75 0F                                     ; jnz .found  (rel8 = 0x6C0 - 0x6B1)
;; Miss: print the token and '?', drop the 0, read on.
E8 A3 FD FF FF                            ; call report_token  (rel32 = 0x459 - 0x6B6)
48 8B 7D 00                               ; mov rdi, [rbp]
48 83 C5 08                               ; add rbp, 8
EB D9                                     ; jmp repl  (rel8 = 0x699 - 0x6C0)
;; .found:
48 8B 04 25 18 30 41 00                   ; mov rax, [LAST_FOUND]
0F B6 48 08                               ; movzx ecx, byte [rax+8] ; flags
F6 C1 01                                  ; test cl, 1         ; IMMEDIATE?
75 14                                     ; jnz .execute  (rel8 = 0x6E5 - 0x6D1)  ; yes: run it now, in either mode
48 8B 04 25 00 30 41 00                   ; mov rax, [STATE]
48 85 C0                                  ; test rax, rax
74 07                                     ; jz .execute  (rel8 = 0x6E5 - 0x6DE)   ; interpret mode: run it
E8 8A FE FF FF                            ; call compile_call  (rel32 = 0x56D - 0x6E3) ; compile mode: CALL xt at HERE
EB B4                                     ; jmp repl  (rel8 = 0x699 - 0x6E5)
;; .execute:
E8 CA FC FF FF                            ; call execute_code  (rel32 = 0x3B4 - 0x6EA)
EB AD                                     ; jmp repl  (rel8 = 0x699 - 0x6EC)
```

Read the loop top-down.

**Step 1: read a token.**

```
call read_word
test rdi, rdi
jz bye_code      ; u = 0: EOF → exit(0)
```

`read_word` (Ch 17) leaves `( c-addr u )` on the data stack, with
the token bytes at `0x412800`.  A length of zero means end of input,
and the loop jumps straight to `bye_code`: `exit(0)`, with whatever
is on the stack abandoned along with the process.

**Step 2: find the word.**

```
call find_code
test rdi, rdi
jnz .found        ; non-zero → match; rdi = xt
```

`( c-addr u )` is exactly what `find_code` consumes, so there is
nothing to marshal.  If `find_code` returns 0 (miss), we fall
through to the miss path.  If it returns non-zero, we have an xt and
we jump to the dispatch path.

**Step 3: miss path.**

```
call report_token                ; print "<token>?\n"
mov rdi, [rbp]; add rbp, 8       ; drop the 0 find_code left
jmp repl
```

The token is still in the buffer and its length is still in `rbx`,
because `find_code` touches neither, so `report_token` (Ch 17) can
echo it: `wibble` comes back as `wibble?`.  The call clobbers `rdi`,
but `rdi` only held `find_code`'s `0`, and the drop that follows
discards that cell anyway, restoring the TOS from before the token.
Then back to the top for the next token.  An unknown word is not
fatal: the REPL reports it and reads on.

**Step 4: dispatch path (`.found`).**

```
mov rax, [LAST_FOUND]            ; entry address
movzx ecx, byte [rax+8]          ; flags byte
test cl, 1                       ; IMMEDIATE?
jnz .execute                     ; yes → execute now regardless of STATE
mov rax, [STATE]
test rax, rax
jz .execute                      ; interpret mode → execute
;; otherwise: compile mode → emit CALL at HERE
```

Two predicates: IMMEDIATE or STATE==0 → execute; otherwise compile.

**Step 5: compile.**

```
call compile_call                ; ( xt -- )  CALL xt at HERE
jmp repl
```

`compile_call` (Ch 18) writes `E8` and the rel32 at HERE, advances
HERE by 5 and drops the xt: the same `CALL rel32` emitter that
`[lit]` uses, and that Ch 10's `call,` rebuilds at the Forth
level.

**Step 6: execute.**

```
call execute_code
jmp repl
```

`execute_code` is the indirect tail-jump from Ch 17 §4.  After the
word runs, we loop back to the top.

That's the whole REPL: six steps, five `call`s into other routines,
and one jump to `bye_code`.

## 3. Why no auto-number parsing in interpret mode?

A classical Forth REPL (like FIG-Forth or gforth) does this:

```
on token:
    if find succeeds: execute or compile
    else if parse-as-number succeeds: push or compile-as-literal
    else: error
```

The seed skips the middle branch, for two reasons.

**Bytes.**  Inlining a `parse_decimal` call into the miss path
would add ~30 bytes of hex (set up the stack, call, branch on
success, push or compile, loop back).  The seed already pays for
`parse_decimal_code` (85 bytes), and every byte of the seed is a
byte someone auditing it has to read.

**One syntax, stated once.**  A number fallback in the REPL would
fix one literal syntax in hex for good.  Keeping numbers behind
`[lit]` leaves that choice to the layers above: a later layer could
add hex, negative or fixed-point literals as ordinary Forth words.
This seed's own layers never needed to: every literal in the library
and the compiler is written `[lit] N`.

The seed is strict: every token must be in the dictionary or
`[lit]`-quoted.  Source that wants to push `42` writes `[lit] 42`,
two tokens where a classical Forth needs one.

## 4. `[lit]` and the IMMEDIATE flag, end to end

When the REPL encounters `[lit]` in interpret mode:
1. Find returns its xt.
2. Dispatch path sees `flags & 1 == 1` → `.execute`.
3. `execute_code` jumps to `bracket_lit_code`.
4. `bracket_lit_code` reads the next token, parses it as decimal,
   leaves the value on the stack, returns.

When the REPL encounters `[lit]` in compile mode:
1. Find returns its xt.
2. Dispatch path sees `flags & 1 == 1` → `.execute` (not
   compile).  *IMMEDIATE words always run now.*
3. `execute_code` jumps to `bracket_lit_code`.
4. `bracket_lit_code` reads the next token, parses it as decimal,
   sees `STATE != 0`, and emits `CALL lit_code` plus the 8-byte cell
   at HERE.

Either way the parsing happens immediately, and the compile-mode
branch lives inside `bracket_lit_code`, not in the REPL.

**A token that isn't a number stops the load.**  If
`parse_decimal_code` returns false, `[lit]` never pushes or compiles
anything: it jumps to `fatal_token`, which prints the token and `?`
and exits with status 2.  Anything that isn't plain decimal digits
hits this: `[lit] -5`, `[lit] 0x41`, `[lit] 12a`.

```sh
echo "[lit] -5 [lit] 48 + emit bye" | ./seed-forth || echo "exit status $?"
# prints "-5?\nexit status 2"
```

So a mistyped literal in your Forth source is the last thing the
seed prints, and the exit status says the seed, not the compiler,
gave up.

## 5. End-to-end trace

Trace `[lit] 42 emit bye`:

1. REPL reads `"[lit]"`.  Find returns xt `0x4005C1`.  Flags `0x01`
   (IMMEDIATE).  Jump to `.execute`.  Execute `bracket_lit_code`.
2. `bracket_lit_code` calls `read_word`, which reads `"42"` and
   leaves `(c-addr=0x412800, len=2)` on the stack.
3. Calls `parse_decimal_code`.  Returns `(n=42, true)`.
4. The flag is true; drop it.
5. STATE is 0 (interpret mode); `42` stays as TOS; return.
6. REPL loops.  Reads `"emit"`.  Find returns xt `0x400254`.  Flags
   `0x00`.  Not IMMEDIATE.  STATE is 0; jump to `.execute`.
   Execute `emit_code`.
7. `emit_code` writes `42` to fd 1 → `*` (ASCII 42).
8. REPL loops.  Reads `"bye"`.  Find returns xt `0x40023A`.
   `.execute`.  Execute `bye_code`.  Kernel terminates.

The second Try-it line below runs exactly this and prints `*`.

## Try it

```sh
./build.sh

echo "[lit] 65 emit bye"               | ./seed-forth   # prints "A"
echo "[lit] 42 emit bye"               | ./seed-forth   # prints "*"
echo "wibble bye"                       | ./seed-forth   # prints "wibble?"

# EOF path:
echo ""                                 | ./seed-forth   # exits cleanly
printf 'bye\n'                          | ./seed-forth   # also fine

# IMMEDIATE flag at work — compile a literal:
echo ": five  [lit] 5 ;  five [lit] 48 + emit bye" | ./seed-forth
# defines a word that pushes 5; calls it; prints '5'

# IMMEDIATE flag on `;` ending the definition (without it, `;`
# would be compiled into foo's body, STATE would stay 1, and the
# rest of the input would be compiled too — nothing would print):
echo ": foo [lit] 88 emit ; foo bye"   | ./seed-forth   # prints "X"
```

To see the miss path with a non-token:

```sh
echo "thisisnotaword bye" | ./seed-forth
# prints "thisisnotaword?", then exits via bye
```

## Exercises

1. **★★★ Extend.** Give the REPL a number fallback: on a miss, try
   `parse_decimal_code` on the token, and push (or compile) the value
   if it succeeds, before reporting `?`.  Where in the REPL does the
   change go?  How many bytes?  (Hint: `find_code` has already
   consumed the token's address; the buffer is still `0x412800` and
   the length is still in `rbx`.)

2. **★★ Trace.** Why does `[lit]` need to be IMMEDIATE?  Trace what would happen
   if you cleared the IMMEDIATE bit in its dictionary entry and
   then compiled `: foo [lit] 5 ;`.

3. **★★ Trace.** The miss path calls `report_token` and then drops
   `find_code`'s `0`.  Would the opposite order work?  (Hint: what
   does `report_token` do to `rdi`, and what does the drop restore
   from `[rbp]`?)

4. **★★ Verify.** The REPL has no `quit` / `abort` mechanism beyond `bye`.  Search
   the `*-cc-*.fth` files for `die` and explain how the C compiler
   handles compile errors instead.

5. **★★★ Extend.** `parse_decimal_code` doesn't handle leading `-`.  Sketch the
   smallest patch that adds negative-number support.  How many
   bytes?  Where does the sign-extension happen?

## Takeaways

- The REPL is 83 bytes of hex that read a token, find it, and
  dispatch on IMMEDIATE and STATE, with a `token?` miss path and a
  `jz bye_code` EOF path.
- The REPL never parses numbers itself, so literals enter only
  through `[lit]`, and a literal `[lit]` cannot read stops the load
  with status 2.
- The dispatch tests the IMMEDIATE bit before STATE, so IMMEDIATE
  words execute in either mode.

## Bridge to Part III: the seed is now a host

**Running count: 1,772 of 1,772 bytes read.**  This chapter added
the last 168: the 85-byte number parser and the 83-byte REPL.

| Chapter | What you read | Bytes | Running total |
|---------|---------------|------:|--------------:|
| 13 | ELF headers, boot code | 186 | 186 |
| 14 | stack and memory primitives | 242 | 428 |
| 15 | arithmetic and logic | 129 | 557 |
| 16 | `bye`, `emit`, `key`, `syscall6` | 200 | 757 |
| 17 | lookup, token reader, naming words | 493 | 1,250 |
| 18 | `:`, `;`, `compile_call`, `lit`, `[lit]` | 287 | 1,537 |
| 19 | `branch`, `0branch` | 67 | 1,604 |
| 20 | number parser, REPL | 168 | 1,772 |

Each chapter's bytes include the headers of the words it read, and
each chapter read one contiguous stretch of the file.

There is no byte of `seed-forth` left that you have to take on
trust.  Part I used these words as black boxes; every one of them is
now a sequence of instructions you have decoded.

Take stock of what that is.  A Forth whose only data structure is a
linked list, whose own I/O moves one byte per system call, which
cannot print a number, and which reads literals only as unsigned
decimal through `[lit]`.  At the far end of Part III is M2-Planet, a
C compiler written in C, and the Stage-A check: our compiler's
`.M1` output for M2-Planet must match the GCC-built reference byte
for byte.  How do you get from here to there?

You can already see both ends.  §5 traced `[lit] 42 emit` printing
`*` by hand.  Here is the same REPL, fed the compiler's Forth first
and one line of C after it:

```sh
{
  cat 010-lib.fth $(tools/compiler-layers.sh)
  echo 'int main(void) { putchar(42); return 0; }'
} | ./seed-forth
chmod +x /tmp/cc-out && /tmp/cc-out         # prints '*'
```

The same 83-byte loop read the compiler as ordinary Forth
definitions, ran `cc-main`, the last word of the Forth, and the
compiler it had just built read the C, wrote an x86-64 ELF to
`/tmp/cc-out`, and exited through `bye`.  Part III is the twelve
chapters between those two `*`s.  It uses no seed internals beyond
the ones you have read (`:`, `;`, `[lit]`, `branch`, `0branch`,
`read_word`, `find`, `here`, `,`) and the Part I words built on
them, such as `if,` and `then,`.

## Reading Part III

Each named section in the next twelve chapters shows the code, then
walks what it does; skim a block for shape and come back when the
walk references it.  The chapters are long because the compiler is,
and if one takes two sittings, that's its size, not your pace.

Three reading aids keep you oriented:

- The **chapter-contract block** at the top names the missing
  capability, the new pattern, the artifact the chapter delivers,
  and the proof link.  It is the chapter's promise.
- The **"After this chapter" block** at the bottom names what the
  compiler can now do, what you can now read, and what that means
  for Stage-A.  It is the chapter's receipt.
- The **rung map and concept index** in `book/CONCEPTS.md` show
  which earlier chapter a given concept came from, so you can
  skip back precisely if the prose assumes something you haven't
  internalised yet.

**Three motifs recur throughout Part III.**

- *Emit, remember, patch.*  Emit a placeholder, stash where you
  put it, patch it once the answer is known.  We met this in
  Ch 11 (`if,` / `then,`) and Ch 19 (`branch` / `0branch`).  It
  returns in Ch 21's output-buffer patch words, which Chs 25–26 use
  for ELF header fields, forward calls and globals, and in Ch 30 at
  full scale for branches, loops, `switch`, and `goto`.

- *Small tables, linear search, newest wins.*  The dictionary
  (Ch 17), macro table (Ch 22), symbol table (Ch 24), label
  table (Ch 30), and typedef / function-symbol lists (Ch 31) all
  share this shape.  Bounded inputs, predictable memory, no
  allocator complexity in the hot path.

- *One buffer per responsibility.*  `cc-in-buf` for input,
  `cc-src-buf` for preprocessed source, `cc-out-buf` for
  emitted bytes, an arena for variable-sized scratch.  Memory
  ownership is whose buffer the bytes live in, not who allocated
  them.

The first problem is the plainest.  The C source arrives on the same
stdin the REPL has been reading token by token, and the compiler
needs all of it in memory before it can preprocess a line, along
with somewhere to put the machine code it emits.  Ch 21 builds both.

Next: Chapter 21 — Arena and I/O Buffers (Part III opens; we leave
the seed and start reading the C compiler).
