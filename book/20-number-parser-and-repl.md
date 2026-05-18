# Chapter 20 — The Number Parser and REPL

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read `parse_decimal_code` and explain why it is invoked via the
  `NUMBER_HOOK` sysvar rather than directly from the REPL loop;
- read the REPL at `0x35E` and trace the read-token / find-word /
  dispatch loop end to end, including the `?\n` miss path;
- explain the role of `[lit]` and why it is the only way to push a
  literal in this seed's interpret mode (the seed does *not*
  auto-parse numbers).

## Source coverage

`000-seed.hex0` `parse_decimal_code @ 0x5FD`, the REPL at `0x35E`,
and the `[lit]` entry in the dictionary.

## Concepts introduced

- **`parse_decimal_code` ( c-addr u -- n true | 0 false ).**  Pure
  decimal: empty length or any non-digit byte returns `(0, false)`;
  success returns `(n, true)`.  Used by `[lit]` in interpret mode
  and by the REPL's number-fallback path if `NUMBER_HOOK` is set.
- **`NUMBER_HOOK` sysvar.**  An optional xt that the REPL consults
  on a `find` miss before printing `?`.  Defaults to 0 (no
  number-fallback); higher layers can install a parser here.
- **The REPL loop.**  Read token; if `read_word` returns 0 (EOF),
  jump to `bye`; else find the token; on hit, dispatch by STATE
  (interpret = execute, compile = emit CALL); on miss, print `?\n`
  and loop.
- **`[lit]` as an immediate compile-helper.**  In interpret mode it
  parses the next token as a decimal and pushes the value.  In
  compile mode it appends `CALL lit` + 8 bytes of the parsed value.
  The seed's only "user-facing" number-pushing word.

## Concepts carried in

- `read_word`, `find_code`, `execute_code` from Ch 17.
- The IMMEDIATE flag + STATE from Ch 10.
- `comma_code` and `lit_code` from Chs 17–18 (used by compile mode).

## Concepts deferred

- Hex / octal / negative number support — not in the seed; would be
  added by setting `NUMBER_HOOK` to a Forth-level parser.

## Section plan

1. **Why no auto-number parsing in interpret mode?**  Trace a
   classical Forth REPL ("if not found, try as number") vs this
   seed's stricter REPL ("if not found, print `?`").  The
   simplification saves bytes in the seed; `[lit]` and
   `NUMBER_HOOK` add it back at the Forth layer.
2. **`parse_decimal_code` byte by byte.**  Skip leading whitespace
   (no — `read_word` already did).  Walk: zero accumulator; for each
   byte, check `0..9`; if good, `acc = acc * 10 + (byte - '0')`;
   else abort with `(0, false)`.  At end, push `(acc, true)`.
3. **The REPL loop at `0x35E`.**
   - Call `read_word`; if `rax == 0` (EOF), `jmp bye_code`.
   - Push `( buf len )`; call `find_code`; pop result.
   - If `0`, fall to miss path: drop the 0, print `?`, print `\n`,
     loop.
   - If non-zero, branch on STATE:
     - STATE=0 (interpret): call `execute_code` with the xt.
     - STATE=1 (compile): emit `CALL xt` at HERE (a 5-byte rel32
       call), unless the entry has IMMEDIATE set (check the flag
       byte) in which case execute now anyway.
4. **`[lit]` in the dictionary.**  Its entry has `flags=01`
   (IMMEDIATE).  Body: parse next token as decimal; in interpret
   mode push the value; in compile mode emit `CALL lit_code` + the
   8 bytes.  Walk the conditional on STATE.
5. **End to end: a token's journey.**  Take `[lit] 42 emit bye`.
   Trace every primitive call: `read_word` → "[lit]" → `find_code`
   → xt of `[lit]` → execute (immediate) → reads "42" via
   `read_word` → `parse_decimal_code` → 42 pushed → `read_word`
   → "emit" → find → execute → prints `*` → `read_word` → "bye"
   → find → execute → exit.

## Canonical chunks

- `<<parse-decimal>>` — `parse_decimal_code @ 0x5FD`.
- `<<repl>>` — the loop at `0x35E`, including miss + EOF paths.
- `<<lit-immediate>>` — the `[lit]` dictionary entry's flags+body
  (the body itself shares logic with `parse_decimal`).

## Try it

```sh
./build.sh
echo "[lit] 65 emit bye" | ./seed-forth     # prints "A"
echo "wibble" | ./seed-forth                 # prints "?"
echo ""    | ./seed-forth                    # exits cleanly (EOF)
```

For the IMMEDIATE-flag check, define a word using a non-immediate
word at compile time and another using `[lit]` (which is
immediate); compare the dictionary bodies.

## Exercises

1. Install a `NUMBER_HOOK` that parses hex literals starting with
   `0x`.  How many lines of Forth?  How does it interact with
   `[lit]`?

2. Why does `[lit]` need to be IMMEDIATE?  Trace what would happen
   if you removed the IMMEDIATE flag and compiled `: foo [lit] 5 ;`.

3. Modify the REPL's miss path to print the unknown token before
   the `?`.  Where in `000-seed.hex0` does the change go?  How
   many extra bytes?

4. The REPL has no `quit` / `abort` machinery beyond `bye`.  How
   does the compiler in Part III handle compile errors then?
   (Hint: search the cc-* files for `die`.)

## Takeaways

- The REPL is ~150 bytes of hex.  It's a four-step loop:
  read-token, find-word, dispatch-by-STATE, print-?-on-miss.
- The seed deliberately does not auto-parse numbers; `[lit]`
  exists to add that back, and `NUMBER_HOOK` is the extension
  point for non-decimal literals.
- IMMEDIATE words live in the dictionary with a flag byte of
  `01`.  The REPL's compile-mode path checks this flag and
  diverts to immediate execution.

Next: Chapter 21 — Arena and I/O Buffers (Part III opens; we leave
the seed and start reading the C compiler).
