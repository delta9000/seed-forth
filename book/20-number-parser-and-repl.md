# Chapter 20 — The Number Parser and REPL

```text
Missing capability: the seed has no way to enter numbers or run user input.
New pattern: a 187-byte loop — read token → find → miss prints ? or dispatch on IMMEDIATE+STATE (execute, or emit a CALL) → loop or bye.
Artifact after this chapter: the seed is now a self-contained host that can load and run the C compiler.
Proof link: this chapter is the bridge into Part III — the host the C compiler sits on top of.
```

The seed has no shell, no command-line flags, no `include` and no
file loader.  Part III builds a working M2-Planet with it anyway,
using one pipe: the comment-stripped library and compiler, then
M2-Planet's C source, all into `./seed-forth`'s stdin.  Something
reads that stream, compiles 4,418 lines of Forth into 367 colon
definitions, and then runs the compiler it just built on the rest of
the input.  That something is a 187-byte loop at `0x35E`
(lines 299–357).  It is the seed's loader, linker and command
interpreter at once, and it is the last code in `000-seed.hex0` you
haven't read.

The REPL reads a token, looks it up, and either executes it
(interpret mode) or compiles a call to it (compile mode).  A miss
prints `?`, and EOF jumps to `bye_code`.  The dispatch tests the
IMMEDIATE flag first and STATE second.  Its companion
`parse_decimal_code` (`@ 0x5FD`, lines 555–585) turns a token like
`"42"` into a number, with the contract `( c-addr u -- n true | 0
false )`; empty input or any byte outside `'0'..'9'`, a leading `-`
included, makes it fail.  The REPL never calls it: numbers enter
only through `[lit]` (Ch 18), a choice §3 examines.

## 1. `parse_decimal_code` ( c-addr u -- n true | 0 false )

The parser is one digit loop with a success tail and a failure tail:

```hex0 chunk=parse-decimal-code
;; ----- parse_decimal_code @ 0x5FD ( c-addr u -- n true | 0 false ) -----
;; Pure-decimal parser. Empty length or any non-digit byte => fail (0, 0).
;; Success => (n, -1) where n = n*10 + digit, per digit.
48 8B 75 00                               ; mov rsi, [rbp]   ; rsi = c-addr
48 83 C5 08                               ; add rbp, 8
48 85 FF                                  ; test rdi, rdi
74 38                                     ; jz .Lfail (rel8 +0x38 → 0x642)
48 31 C0                                  ; xor rax, rax     ; accumulator
48 89 F9                                  ; mov rcx, rdi     ; remaining count
;; .Lloop:
48 0F B6 16                               ; movzx rdx, byte [rsi]
48 83 EA 30                               ; sub rdx, '0'
78 28                                     ; js .Lfail (rel8 +0x28)  ; signed: < '0'
48 83 FA 09                               ; cmp rdx, 9
7F 22                                     ; jg .Lfail (rel8 +0x22)  ; > '9'
48 8D 04 80                               ; lea rax, [rax+rax*4]    ; rax * 5
48 01 C0                                  ; add rax, rax              ; rax * 10
48 01 D0                                  ; add rax, rdx              ; + digit
48 FF C6                                  ; inc rsi
48 FF C9                                  ; dec rcx
75 DE                                     ; jne .Lloop (rel8 -34)
;; success:
48 83 ED 08                               ; sub rbp, 8
48 89 45 00                               ; mov [rbp], rax            ; spill n
48 C7 C7 FF FF FF FF                      ; mov rdi, -1               ; success flag
C3
;; .Lfail:
48 83 ED 08                               ; sub rbp, 8
48 C7 45 00 00 00 00 00                   ; mov qword [rbp], 0
48 31 FF                                  ; xor rdi, rdi
C3

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

Two things to flag.

**This is a one-shot parser, not a partial parser.**  If any byte
fails the range check, the *whole token* fails.

**No sign handling.**  `-42` fails at the `-` byte (`0x2D < 0x30`,
so `js` triggers).  The C compiler in Part III treats negation as a
unary operator, so the restriction is invisible to it.

## 2. The REPL loop

The loop that drives everything is 187 bytes:

```hex0 chunk=repl
;; ----- repl @ 0x35E -----
;; Read tokens, find them, execute (or compile, depending on STATE).
;; On EOF: jmp bye_code.
;;
;; @0x35E: call read_word (rel32 = 0x259 - 0x363 = -266)
E8 F6 FE FF FF
48 85 C0                                  ; test rax, rax
;; @0x366: jz .repl_done rel32 (target 0x414, rel = 0xA8)
0F 84 A8 00 00 00
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi   ; spill old TOS
48 C7 C7 00 28 41 00                      ; mov rdi, 0x412800
48 83 ED 08                               ; sub rbp, 8
48 89 7D 00                               ; mov [rbp], rdi   ; spill addr
48 89 C7                                  ; mov rdi, rax     ; TOS = length
;; @0x386: call find_code (rel32 = 0x1C5 - 0x38B = -454)
E8 3A FE FF FF
48 85 FF                                  ; test rdi, rdi
75 32                                     ; jnz .have_xt (rel8 +0x32 → 0x3C2)
;; miss: drop the 0; print '?\n'; loop
48 8B 7D 00
48 83 C5 08
48 83 ED 08
48 89 7D 00
48 C7 C7 3F 00 00 00                      ; mov rdi, '?'
;; @0x3A7: call emit_code (rel32 = 0x0DE - 0x3AC = -718)
E8 32 FD FF FF
48 83 ED 08
48 89 7D 00
48 C7 C7 0A 00 00 00                      ; mov rdi, '\n'
;; @0x3BB: call emit_code (rel32 = 0x0DE - 0x3C0 = -738)
E8 1E FD FF FF
EB 9C                                     ; jmp repl (rel8 -0x64 → 0x35E)
;; .have_xt @ 0x3C2: handle interpret-vs-compile
48 8B 04 25 18 30 41 00                   ; mov rax, [LAST_FOUND]
0F B6 48 08                               ; movzx ecx, byte [rax+8]   ; flags
F6 C1 01                                  ; test cl, 1
75 37                                     ; jnz .interpret (rel8 +0x37 → 0x40A)
48 8B 04 25 00 30 41 00                   ; mov rax, [STATE]
48 85 C0                                  ; test rax, rax
74 2A                                     ; jz .interpret (rel8 +0x2A → 0x40A)
;; compile mode: emit CALL <xt = rdi> at HERE
48 8B 04 25 10 30 41 00                   ; mov rax, [HERE]
C6 00 E8                                  ; mov byte [rax], 0xE8     ; CALL opcode
48 83 C0 05                               ; add rax, 5                ; next-ip
48 29 C7                                  ; sub rdi, rax              ; rdi = xt - next-ip = rel32
89 78 FC                                  ; mov [rax-4], edi          ; store rel32
48 89 04 25 10 30 41 00                   ; mov [HERE], rax           ; HERE += 5
48 8B 7D 00                               ; mov rdi, [rbp]            ; refill TOS
48 83 C5 08                               ; add rbp, 8
;; @0x405: jmp repl (rel32 = 0x35E - 0x40A = -0xAC)
E9 54 FF FF FF
;; .interpret @ 0x40A:
;; @0x40A: call execute_code (rel32 = 0x24C - 0x40F = -451)
E8 3D FE FF FF
;; @0x40F: jmp repl (rel32 = 0x35E - 0x414 = -0xB6)
E9 4A FF FF FF
;; .repl_done @ 0x414: jmp bye_code (rel32 = 0x0D2 - 0x419 = -0x347)
E9 B9 FC FF FF

```

Read the loop top-down.

**Step 1: read a token.**

```
call read_word
test rax, rax
jz .repl_done    ; EOF → exit
```

`read_word` returns the token length in `rax` and the bytes in
`[0x412800]`.  If the length is zero, we hit EOF; jump to the
`.repl_done` tail (which itself jumps to `bye_code`).

**Step 2: set up `find_code`'s stack.**

The data stack needs to look like `( c-addr u -- )` for
`find_code`.  We push the old TOS (whatever was there before),
push the buffer address (`0x412800`), and put the length in `rdi`
as the new TOS.

```
sub rbp, 8; mov [rbp], rdi      ; spill old TOS
mov rdi, 0x412800               ; rdi = c-addr (TIB)
sub rbp, 8; mov [rbp], rdi      ; spill c-addr to data stack
mov rdi, rax                    ; rdi = length (new TOS)
```

This is the same setup that `tick_code` uses (Ch 17 §7).  After it,
`find_code` can be called with no further marshalling.

**Step 3: find the word.**

```
call find_code
test rdi, rdi
jnz .have_xt      ; non-zero → match; rdi = xt
```

If `find_code` returns 0 (miss), we fall through to the miss path.
If it returns non-zero, we have an xt and we jump to the dispatch
path.

**Step 4: miss path.**

```
mov rdi, [rbp]; add rbp, 8       ; drop the 0 find_code left on data stack
sub rbp, 8; mov [rbp], rdi       ; re-spill in preparation for the '?' push
mov rdi, '?'                     ; new TOS = '?'
call emit_code
sub rbp, 8; mov [rbp], rdi       ; spill again for '\n'
mov rdi, '\n'                    ; new TOS = '\n'
call emit_code
jmp .repl
```

The pop/spill pair at the top is the Forth-stack "drop and replace
TOS" idiom: the seed's calling convention keeps TOS in `rdi`, so to
*replace* what's on top we have to pop the spilled cell (restoring
the next-below value into `rdi`), then push a new value (spilling
`rdi` and loading the new one).  Net effect: the `0` that
`find_code` left on the data stack is gone, and `'?'` takes its
place.  The second pair does the same for `'\n'`.  Print, then loop
back to read the next token.

The miss path doesn't consult `NUMBER_HOOK`.  The slot exists in the
sysvar layout, but nothing reads it.

**Step 5: dispatch path (`.have_xt`).**

```
mov rax, [LAST_FOUND]            ; entry address
movzx ecx, byte [rax+8]          ; flags byte
test cl, 1                       ; IMMEDIATE?
jnz .interpret                   ; yes → execute now regardless of STATE
mov rax, [STATE]
test rax, rax
jz .interpret                    ; interpret mode → execute
;; otherwise: compile mode → emit CALL at HERE
```

Two predicates: IMMEDIATE or STATE==0 → execute; otherwise compile.

**Step 6: compile.**

```
mov rax, [HERE]
mov byte [rax], 0xE8             ; CALL opcode
add rax, 5                       ; next-ip
sub rdi, rax                     ; rdi = xt - next-ip = rel32 displacement
mov [rax-4], edi                 ; back-patch rel32
mov [HERE], rax                  ; HERE += 5
mov rdi, [rbp]; add rbp, 8       ; pop the now-stale TOS
jmp .repl
```

This is the same `CALL rel32` emitter that Ch 11's `comma-call`
uses at the Forth level.  Here it's inlined into the REPL.

**Step 7: execute.**

```
call execute_code
jmp .repl
```

`execute_code` is the indirect tail-jump from Ch 17 §4.  After the
word runs, we loop back to the top.

**Step 8: exit.**

```
.repl_done:
jmp bye_code
```

A single rel32 jump to `exit(0)`.

That's the whole REPL: eight steps, four `call`s into other
primitives, one `jmp` to `bye_code`.

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
`parse_decimal_code` (~85 bytes); making it reachable from the
REPL would push the total past the 2,040-byte budget if anything
else in the file grew.

**Composability.**  By *not* hard-coding decimal parsing, the seed
leaves the door open for higher layers to add their own number
parsing: hex, octal, negative numbers, fixed-point.  The
`NUMBER_HOOK` sysvar at `0x413020` is the seed's stub for this; it
gets initialised to 0 in `<<sysvar-init>>` and is never read by
the seed itself.  A REPL with a number fallback could consult an xt
that a Forth-level extension installs there.

The seed is strict: every token must be in the dictionary or
`[lit]`-quoted.  Source that wants to push `42` writes `[lit] 42`,
two tokens where a classical Forth needs one.

## 4. `[lit]` and the IMMEDIATE flag, end to end

When the REPL encounters `[lit]` in interpret mode:
1. Find returns its xt.
2. Dispatch path sees `flags & 1 == 1` → `.interpret`.
3. `execute_code` jumps to `bracket_lit_code`.
4. `bracket_lit_code` reads the next token, parses it as decimal,
   pushes the value, returns.

When the REPL encounters `[lit]` in compile mode:
1. Find returns its xt.
2. Dispatch path sees `flags & 1 == 1` → `.interpret` (not
   compile).  *IMMEDIATE words always run now.*
3. `execute_code` jumps to `bracket_lit_code`.
4. `bracket_lit_code` reads the next token, parses it as decimal,
   sees `STATE != 0`, emits `CALL lit_code + 8-byte cell` at HERE.

Either way the parsing happens immediately, and the compile-mode
branch lives inside `bracket_lit_code`, not in the REPL.

**Unparseable tokens silently become 0.**  `bracket_lit_code` pops
`parse_decimal_code`'s flag and throws it away without testing it.
On failure the parser leaves `0` under the flag, so `[lit]` pushes
(or compiles) `0` and carries on, with no `?` and no error.  Anything that
isn't plain decimal digits hits this: `[lit] -5`, `[lit] 0x41`,
`[lit] 12a`.

```sh
echo "[lit] -5 [lit] 48 + emit bye" | ./seed-forth
# prints "0": the -5 became 0, and 0 + 48 = '0'
```

The token is consumed either way, so the REPL doesn't see it
again.  If a literal in your Forth source comes out as zero, check
it for a sign, a `0x` prefix, or a stray character.

## 5. End-to-end trace

Trace `[lit] 42 emit bye`:

1. REPL reads `"[lit]"`.  Find returns xt `0x6CF`.  Flags `0x01`
   (IMMEDIATE).  Jump to `.interpret`.  Execute `bracket_lit_code`.
2. `bracket_lit_code` calls `read_word`, gets `"42"` with length 2.
3. Pushes `(c-addr=0x412800, len=2)` for `parse_decimal_code`.
4. Calls `parse_decimal_code`.  Returns `(n=42, true)`.
5. STATE is 0 (interpret mode); push `42` as TOS and return.
6. REPL loops.  Reads `"emit"`.  Find returns xt `0x46D`.  Flags
   `0x00`.  Not IMMEDIATE.  STATE is 0; jump to `.interpret`.
   Execute `emit_code`.
7. `emit_code` writes `42` to fd 1 → `*` (ASCII 42).
8. REPL loops.  Reads `"bye"`.  Find returns xt `0x45A`.
   `.interpret`.  Execute `bye_code`.  Kernel terminates.

The second Try-it line below runs exactly this and prints `*`.

## Try it

```sh
./build.sh

echo "[lit] 65 emit bye"               | ./seed-forth   # prints "A"
echo "[lit] 42 emit bye"               | ./seed-forth   # prints "*"
echo "wibble bye"                       | ./seed-forth   # prints "?\n"

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
# prints "?\n", then exits via bye
```

## Exercises

1. **★★★ Extend.** Install a `NUMBER_HOOK` that parses hex literals (e.g., `0x1F`).
   Where in the REPL does it need to be consulted?  How many bytes
   of patching?  (Hint: you'll need to modify the miss path to call
   the hook instead of jumping straight to `?\n`.)

2. **★★ Trace.** Why does `[lit]` need to be IMMEDIATE?  Trace what would happen
   if you cleared the IMMEDIATE bit in its dictionary entry and
   then compiled `: foo [lit] 5 ;`.

3. **★★★ Modify.** Modify the REPL's miss path to print the unknown token before
   the `?`.  Where in `000-seed.hex0` does the change go?  How
   many extra bytes does it cost?  (Hint: you have to call
   `emit_code` in a loop over the token bytes; `0x412800` is the
   buffer address.)

4. **★★ Verify.** The REPL has no `quit` / `abort` mechanism beyond `bye`.  Search
   the `*-cc-*.fth` files for `die` and explain how the C compiler
   handles compile errors instead.

5. **★★★ Extend.** `parse_decimal_code` doesn't handle leading `-`.  Sketch the
   smallest patch that adds negative-number support.  How many
   bytes?  Where does the sign-extension happen?

## Takeaways

- The REPL is 187 bytes of hex that read a token, find it, and
  dispatch on IMMEDIATE and STATE, with a `?` miss path and a
  `jmp bye_code` EOF path.
- The REPL never parses numbers itself, so literals enter only
  through `[lit]`, and `NUMBER_HOOK` stays an unwired extension
  point.
- The dispatch tests the IMMEDIATE bit before STATE, so IMMEDIATE
  words execute in either mode.

## Bridge to Part III: the seed is now a host

**Running count: 2,040 of 2,040 bytes read.**  This chapter added
the last 272: the 85-byte number parser and the 187-byte REPL.

| Chapter | What you read | Bytes | Running total |
|---------|---------------|------:|--------------:|
| 13 | ELF headers, boot code | 210 | 210 |
| 14 | stack and memory primitives | 119 | 329 |
| 15 | arithmetic, logic, `/`'s entry | 86 | 415 |
| 16 | `bye`, `emit`, `key`, `syscall6` | 165 | 580 |
| 17 | lookup, token reader, dictionary | 868 | 1,448 |
| 18 | `:`, `;`, `lit`, `[lit]` | 286 | 1,734 |
| 19 | `branch`, `0branch` | 34 | 1,768 |
| 20 | number parser, REPL | 272 | 2,040 |

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
  cat 010-lib.fth [0-9][0-9][0-9]-cc-*.fth | sed -e 's/\\.*$//' -e 's/([^)]*)//g'
  echo 'int main(void) { putchar(42); return 0; }'
} | grep -v '^[[:space:]]*$' | ./seed-forth
chmod +x /tmp/cc-out && /tmp/cc-out         # prints '*'
```

The same 187-byte loop read the compiler as ordinary Forth
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

- *One buffer per responsibility.*  `cc-src-buf` for input,
  `cc-prep-out-buf` for preprocessed source, `cc-out-buf` for
  emitted bytes, an arena for variable-sized scratch.  Memory
  ownership is whose buffer the bytes live in, not who allocated
  them.

The first problem is the plainest.  The C source arrives on the same
stdin the REPL has been reading token by token, and the compiler
needs all of it in memory before it can preprocess a line, along
with somewhere to put the machine code it emits.  Ch 21 builds both.

Next: Chapter 21 — Arena and I/O Buffers (Part III opens; we leave
the seed and start reading the C compiler).
