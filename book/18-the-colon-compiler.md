# Chapter 18 — The Colon Compiler

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read `colon_code` byte for byte and explain what each section
  contributes to building a dictionary header;
- read `semicolon_code` and explain why it sets the IMMEDIATE flag
  on itself at assembly time, not at runtime;
- read `lit_code` and explain the in-line literal convention (the
  8 bytes immediately following the `CALL lit` site).

## Source coverage

`000-seed.hex0` `colon_code @ 0x2D4`, `semicolon_code @ 0x33B`,
`lit_code @ 0x419`.  Roughly 100 lines of hex.

## Concepts introduced

- **`colon_code` ( -- ) parses a name and builds a header.**  Calls
  `read_word`, copies the link/flags/name-len/name bytes into HERE,
  flips STATE to 1.  The header is exactly `10 + name-len` bytes.
- **`semicolon_code` ( -- ) appends `ret` and flips STATE back.**
  Writes `0xC3` at HERE, advances HERE by 1, sets STATE=0.  The
  `;` entry in the dictionary itself has the IMMEDIATE flag set
  at assembly time (its dictionary header has `flags=01`).
- **`lit_code` ( -- v ) reads its own inline 8-byte cell.**  Pops
  the return address (which points at the 8 bytes immediately after
  the `CALL lit` site); fetches the cell; pushes it; advances the
  return address past the cell so we resume after the slot.

## Concepts carried in

- `read_word` from Ch 17 (called by `colon_code`).
- The dictionary layout from Ch 17.
- The `c,`-style HERE advancement from Ch 2 — but here in raw hex.

## Concepts deferred

- The interplay of `:` with `STATE` and `find_code` in the REPL —
  Ch 20.
- `branch_code` and `0branch_code` (which share `lit_code`'s
  inline-slot convention) — Ch 19.

## Section plan

1. **`colon_code`'s anatomy.**  Five sections:
   (a) read token into the token buffer;
   (b) capture current HERE as the new entry's body start;
   (c) write `LATEST @` as the link cell at HERE; bump HERE 8;
   (d) write `00` flags + token length + token bytes;
   (e) update `LATEST` to point at the new entry; set STATE=1.
2. **The byte-copy loop inside `colon_code`.**  Walk the `rep movsb`
   or the equivalent hand-loop.  Each token byte goes into the
   header.
3. **`semicolon_code` in five bytes.**  `mov byte [HERE], C3 ; inc
   HERE ; mov [STATE], 0 ; ret`.  Annotate.
4. **Why `;` is IMMEDIATE at assembly time.**  Its dictionary entry
   carries `flags=01`.  The REPL's compile-mode handler checks this
   flag; if set, the word runs *now* instead of being appended to
   the body being compiled.  Without this, `;` would be appended to
   itself in an infinite loop.
5. **`lit_code` and the inline-cell trick.**  When a compile-time
   number is encountered, the REPL emits `CALL lit` followed by 8
   bytes of the literal value.  At runtime, `lit_code` reads its
   *own* return address (= the byte just after `CALL lit` = the
   first byte of the slot), fetches the 8 bytes, advances the
   return address past them, and returns.

## Canonical chunks

- `<<colon-code>>` — roughly 100 bytes at `0x2D4`.
- `<<semicolon-code>>` — ~30 bytes at `0x33B`.
- `<<lit-code>>` — ~18 bytes at `0x419`.

## Try it

```sh
./build.sh
echo ': square dup * ;  [lit] 7 square [lit] 48 + emit bye' | ./seed-forth
# 7*7=49, +48='1', prints "1"
echo ': five [lit] 5 ;  five [lit] 48 + emit bye' | ./seed-forth
# 5+48='5'
```

For each test, predict the bytes emitted at `HERE` by `:` and `;`
before running.

## Exercises

1. The header built by `:` is exactly `10 + name-len` bytes.
   Compute it for `: square`.  Now compute it for a 240-character
   name.  Does the name-length byte limit you to 255?  What would
   happen at length 256?

2. `;`'s appended `ret` (`C3`) is the only thing connecting a colon
   definition to its caller.  Why is `ret` enough?  (Hint: how was
   the colon definition entered — via `CALL` or via `JMP`?)

3. `lit_code` advances the return address by 8.  Trace what would
   happen if you forgot to advance.  Now what if you advanced by 7
   or 9?

4. Write a hypothetical `2lit_code` that reads 16 inline bytes and
   pushes two cells.  How would the compile-mode REPL emit it?

## Takeaways

- `:` and `;` are 130 bytes of hex between them — most of which is
  parsing the name and copying it into a header.  The actual "open
  / close a compilation unit" is a flag flip and a `ret` byte.
- `;` is IMMEDIATE at assembly time, with its flags byte set to
  `01` in the dictionary.  This is the only IMMEDIATE word in the
  seed; all other immediates are added at the Forth layer (Ch 10).
- `lit_code`'s in-line-cell trick is the model for the
  `branch_code`/`0branch_code` we read in the next chapter.

Next: Chapter 19 — Branches and Inline Cells.
