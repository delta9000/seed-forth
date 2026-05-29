# Chapter 20 — The Number Parser and REPL

```text
Missing capability: the seed has no way to enter numbers or run user input.
New pattern: a 187-byte loop — read token → find → dispatch on IMMEDIATE+STATE → decimal parse → loop or bye.
Artifact after this chapter: the seed is now a self-contained host that can load and run the C compiler.
Proof link: this chapter is the bridge into Part III — the host the C compiler sits on top of.
```

The last two primitives in the seed close Part II: `parse_decimal_code`
(`@ 0x5FD`, lines 555–585) and the REPL loop itself (`@ 0x35E`,
lines 299–357, 187 bytes of hex).  `parse_decimal_code` is a pure
decimal parser with the contract `( c-addr u -- n true | 0 false )`;
empty input or any byte outside `'0'..'9'` (including a leading
`-`) makes it fail.  The REPL is five logical sections (read token,
EOF guard, find word, miss path, dispatch path), and the dispatch
path is where compile-vs-interpret mode finally fuses, branching on
the IMMEDIATE flag and on STATE to choose between `execute_code`
and `comma_code`.

By the end of the chapter you'll be able to read both bodies end
to end, explain why `[lit]` (Ch 18) is the only way to push a
literal in interpret mode (the REPL does not auto-parse numbers),
trace the `?\n` miss path, and read the `NUMBER_HOOK` sysvar
(`0x413020`) as the unused extension point a higher layer could
wire up for hex, octal, or negative literals.  That closes the
seed: every byte of `000-seed.hex0` has now been accounted for.
Part III picks up with the C compiler written in Forth on top of
this REPL.

---

The REPL is the seed's outer loop and the last primitive we have
to read.  Every primitive we've covered up to this point has been
some kind of building block — a stack op, an arithmetic op, a
syscall wrapper, a header builder, a branch.  The REPL stitches
them together.

Its job is to read tokens forever, look each one up in the
dictionary, and either *execute* it (interpret mode) or *compile a
call to it* (compile mode).  On a lookup miss, it prints `?`; on
EOF, it jumps to `bye_code`.  That's the whole loop, expressible
in eight English words, encoded in 187 bytes of hex (offsets
`0x35E`–`0x418`).

The number parser is the supporting cast.  `parse_decimal_code`
is what `[lit]` (Ch 18) calls to convert a token like `"42"` into
the cell value `42`.  It is *not* called from the REPL loop —
that's a deliberate choice we examine in §3.

## 1. `parse_decimal_code` ( c-addr u -- n true | 0 false )

```hex0 chunk=parse-decimal-code
;; ----- parse_decimal_code @ 0x5FD ( c-addr u -- n true | 0 false ) -----
;; Pure-decimal parser. Empty length or any non-digit byte => fail (0, 0).
;; Success => (n, -1) where n = sum of digits * 10.
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

The `lea rax, [rax + rax*4]; add rax, rax` pair multiplies by 10 in
two instructions and no temporary register.  `lea rax, [rax +
rax*4]` is `rax = rax*5`; then `add rax, rax` doubles it.

Success path:
- Push the parsed value `n` onto the data stack (it goes into
  the new under-TOS slot via `mov [rbp], rax`).
- Set `rdi` to `-1` (Forth-canonical true).

Failure path:
- Push the cell `0` onto the data stack.
- Set `rdi` to `0` (Forth-canonical false).

Two things to flag.

**This is a one-shot parser, not a partial parser.**  If any byte
fails the range check, the *whole token* fails.  There is no
"consumed N digits and stopped at a separator" — the entire token
must be all digits, or it's not a number.

**No sign handling.**  `-42` would fail at the `-` byte (`0x2D <
0x30`, the `js` test triggers).  Negative literals do not exist in
the seed's number parser.  The C compiler in Part III handles
negation as a unary operator, not as part of the literal — so the
restriction is invisible to it.

## 2. The REPL loop

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

**Step 1 — read a token.**

```
call read_word
test rax, rax
jz .repl_done    ; EOF → exit
```

`read_word` returns the token length in `rax` and the bytes in
`[0x412800]`.  If the length is zero, we hit EOF; jump to the
`.repl_done` tail (which itself jumps to `bye_code`).

**Step 2 — set up `find_code`'s stack.**

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

**Step 3 — find the word.**

```
call find_code
test rdi, rdi
jnz .have_xt      ; non-zero → match; rdi = body address (xt)
```

If `find_code` returns 0 (miss), we fall through to the miss path.
If it returns non-zero, we have an xt and we jump to the dispatch
path.

**Step 4 — miss path.**

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

Notice that the miss path doesn't consult `NUMBER_HOOK` — that's a
feature that exists in the sysvar layout but isn't wired up here.

**Step 5 — dispatch path (`.have_xt`).**

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

**Step 6 — compile.**

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

**Step 7 — execute.**

```
call execute_code
jmp .repl
```

`execute_code` is the indirect tail-jump from Ch 17 §4.  After the
word runs, we loop back to the top.

**Step 8 — exit.**

```
.repl_done:
jmp bye_code
```

A single rel32 jump to `exit(0)`.

That's the whole REPL.  Eight steps, four `call`s into other
primitives (`read_word`, `find_code`, `emit_code`, `execute_code`),
one `jmp` to `bye_code`.

## 3. Why no auto-number parsing in interpret mode?

A classical Forth REPL (like FIG-Forth or gforth) does this:

```
on token:
    if find succeeds: execute or compile
    else if parse-as-number succeeds: push or compile-as-literal
    else: error
```

The seed *does not* do step 2.  Tokens that aren't dictionary
words just print `?`.

Why?  Two reasons.

**Bytes.**  Inlining a `parse_decimal` call into the miss path
would add ~30 bytes of hex (set up the stack, call, branch on
success, push or compile, loop back).  The seed already pays for
`parse_decimal_code` (~50 bytes); making it reachable from the
REPL would push the total past the 2,040-byte budget if anything
else in the file grew.

**Composability.**  By *not* hard-coding decimal parsing, the seed
leaves the door open for higher layers to add their own number
parsing — hex, octal, negative numbers, fixed-point.  The
`NUMBER_HOOK` sysvar at `0x413020` is the seed's stub for this; it
gets initialised to 0 in `<<sysvar-init>>` and is never read by
the seed itself, but a Forth-level extension can install an xt
there and *the existing REPL* (if it had number-fallback support)
would consult it.

For now the seed is strict: every token must be in the dictionary
or `[lit]`-quoted.  Source code that wants to push `42` writes
`[lit] 42` — a two-token incantation that costs one extra read
per literal, but pays only the IMMEDIATE-word lookup once.

## 4. `[lit]` and the IMMEDIATE flag, end to end

Recap from Ch 18: `[lit]` is an IMMEDIATE word.  Its body is
`bracket_lit_code` at `0x652`.  Its dictionary entry has `flags =
01`.

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

Either way, the parsing happens immediately.  The compile-mode
branch lives inside `bracket_lit_code`, not in the REPL.  That's
why `[lit]` *has* to be IMMEDIATE: it needs to run during
compilation to do the parsing-and-emitting.

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

You can confirm this is what happens by piping `echo "[lit] 42
emit bye"` into the binary and observing `*` printed.

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

# IMMEDIATE flag preventing infinite recursion in `;`:
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

- The REPL is 187 bytes of hex.  Its loop is read-token →
  find-word → dispatch-by-IMMEDIATE-and-STATE, with a print-`?`
  miss path and a `jmp bye_code` EOF path.
- The seed *deliberately does not* auto-parse numbers in the REPL
  loop.  `[lit]` exists at the Forth-visible level to add that
  back; `NUMBER_HOOK` is the unwired extension point for richer
  literals (hex, negative, etc.).
- IMMEDIATE words live in the dictionary with `flags = 01`.  The
  REPL's dispatch path checks this bit *first*, before STATE — so
  IMMEDIATE words always execute, no matter which mode the REPL
  is in.

## Bridge to Part III: the seed is now a host

Part I taught the Forth vocabulary while treating the seed
primitives as black boxes.  Part II opened those boxes and showed
the exact bytes behind token reading, dictionary lookup, compiling,
branching, literals, and the REPL loop.  The inversion is complete:
the words that were machine-code mysteries in Part I are now tools
we can trust.

The remaining twelve chapters use those tools as the *host* for a C
compiler.  You should not expect another tour of seed internals.
Instead, Part III follows compiler infrastructure built out of the
same primitives you have just seen in machine code — `:`, `;`, `[lit]`,
`if,`, `then,`, `branch`, `0branch`, `read_word`, `find`, `here`, `,`
— until the compiler emits `.M1` text matching the GCC-built
M2-Planet reference on the stage-A inputs.

## Reading Part III

The next twelve chapters have a consistent shape: each named section
shows you the relevant code, then walks what it does.  You can skim
each code block once for shape and come back when the walk
references it, or read it line-by-line — both work.  The chapters
are long because the compiler is, not because the prose is dense;
if a chapter takes two sittings, that's its size, not your pace.

Three reading aids are placed in every Part III chapter to keep
you oriented:

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

**Three recurring motifs are worth memorising.**  Once you spot
one you understand a dozen.

- *Emit, remember, patch.*  Emit a placeholder, stash where you
  put it, patch it once the answer is known.  We met this in
  Ch 11 (`if,` / `then,`) and Ch 19 (`branch` / `0branch`).  It
  returns in Ch 21 for ELF header fields, Chs 25–26 for forward
  calls and globals, and Ch 30 at full scale for branches,
  loops, `switch`, and `goto`.

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

If a Part III chapter ever feels like it stopped explaining and
started listing, look for whichever of those three patterns it is
using and the walk will resolve.

Next: Chapter 21 — Arena and I/O Buffers (Part III opens; we leave
the seed and start reading the C compiler).
