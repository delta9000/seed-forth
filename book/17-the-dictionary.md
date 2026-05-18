# Chapter 17 — The Dictionary

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- explain the dictionary entry layout `link(8) flags(1) name-len(1)
  name(N) body(M)` and walk the linked list backwards from `LATEST`;
- read `find_code` and explain its loop, the `bytes-eq`-style name
  match, and the `LAST_FOUND` sysvar update;
- read `here_code`, `comma_code`, `execute_code`, `tick_code`, and
  `read_word`, and explain what each contributes to the parse-then-
  resolve cycle.

## Source coverage

`000-seed.hex0` lines roughly 171–262.  Six primitive bodies:
`find_code @ 0x1C5`, `here_code @ 0x21B`, `comma_code @ 0x22C`,
`execute_code @ 0x24C`, `tick_code` (probably near the dictionary
entries), and `read_word @ 0x259`.

## Concepts introduced

- **The dictionary as a linked list of headers.**  Each entry stores
  a pointer to the previous entry's link cell.  `LATEST` is the head;
  walking link-cell-to-link-cell ends at a null pointer at the entry
  for the first hand-written word.
- **`find_code` ( c-addr u -- xt-or-0 ).**  Walks the chain; compares
  each entry's name (length + bytes) to the given token; returns the
  body address on success or `0` on miss.  Updates `LAST_FOUND` as a
  side effect (used by `'` and the seed's compile-mode CALL emitter).
- **`here_code` ( -- HERE ).**  Pushes the *contents* of the HERE
  sysvar (the next-byte-to-write address).
- **`comma_code` ( v -- ).**  Writes 8 bytes from TOS at HERE and
  advances HERE by 8.  The cell-sized writer.
- **`execute_code` ( xt -- ).**  Pops an xt and `CALL`s it.  How
  dispatch happens at the seed layer.
- **`tick_code` ( -- xt ).**  Reads the next token and looks it up;
  returns the xt or aborts.
- **`read_word` ( -- buf-addr count ).**  Reads a whitespace-
  delimited token from input into the token buffer at `0x412800`.

## Concepts carried in

- The sysvar layout from Ch 13 (`LATEST`, `HERE`, `LAST_FOUND`).
- `bytes-eq`'s comparison style from Ch 12 — but here implemented in
  hex, not Forth.
- The token-buffer page convention from Ch 13.

## Concepts deferred

- The dictionary entries themselves (the `--- bye @ 0x44D ---` style
  headers) — they live in the source right after the primitive
  bodies; we'll cover them as a single chunk in this chapter's source
  emission.
- The REPL's use of `find_code` and `execute_code` — Ch 20.

## Section plan

1. **The header layout, illustrated.**  Draw three consecutive
   dictionary entries — `dup`, `drop`, `swap` — with their link
   cells pointing backwards.  Show `LATEST` pointing at the head.
2. **`find_code`'s walk.**  Outer loop: chase `link`s.  Inner loop:
   byte-compare the name.  ~80 bytes of x86 to do what `bytes-eq` +
   loop does in Forth, but inline.
3. **`here_code` and `comma_code`.**  The two cell-level memory
   primitives we'll lean on in Chs 18 and 19.
4. **`execute_code` is one `jmp rdi`.**  Or `pop rax; jmp rax`,
   depending on the seed's exact encoding.  Either way: indirect
   jump to the xt, no return frame.
5. **`tick_code`: read + find + error or push.**  The seed's `'`
   primitive.  Read its bytes; trace the case where the next token
   is unknown.
6. **`read_word`: byte-by-byte token assembly.**  Skip leading
   whitespace; copy non-whitespace bytes to the token buffer; stop on
   whitespace or EOF; return `( buf len )`.

## Canonical chunks

- `<<find-code>>` — ~80 bytes at `0x1C5`.
- `<<here-code>>` — small wrapper at `0x21B`.
- `<<comma-code>>` — small wrapper at `0x22C`.
- `<<execute-code>>` — at `0x24C`.
- `<<read-word>>` — at `0x259`.
- `<<tick-code>>` — at its address near the dictionary entries.
- `<<dictionary-entries>>` — the entire `--- bye @ 0x44D ---` ...
  `--- 0branch @ 0x5E7 ---` block, treated as one chunk because it's
  a single contiguous list of headers.

## Try it

```sh
./build.sh
# Build a tiny defs file and watch find_code resolve names:
echo ': greet [lit] 72 emit [lit] 105 emit bye ;  greet' | ./seed-forth
# prints "Hi" — `greet` is found in the dictionary built by `:`.

# Unknown words print "?":
echo 'wibble' | ./seed-forth
# prints "?"
```

## Exercises

1. The dictionary is a singly linked list from newest to oldest.
   Why not oldest to newest?  (Hint: `find_code` checks the most
   recent definition first — shadowing is free.)

2. Why does `find_code` update a `LAST_FOUND` sysvar instead of
   returning a flag?  (Hint: the REPL needs both the xt *and* the
   IMMEDIATE flag.  Where does the flag live?)

3. Modify `read_word` (in a copy of `000-seed.hex0`) to recognise
   `\` as a line-comment marker.  How many extra bytes?

4. Walk the dictionary by hand: starting from `LATEST @`, follow
   eight link cells.  What's the name at each step?

## Takeaways

- The dictionary is the seed's only data structure.  No hash table,
  no symbol table — just a linked list walked by `find_code`.
- `find_code` does name comparison inline in 80 bytes.  Forth-level
  code (`bytes-eq`, Ch 12) re-implements the same logic in 13 lines.
- `read_word` is the only token reader in the system; everything
  parsed — including numbers, including `[lit]`, including names
  — starts here.

Next: Chapter 18 — The Colon Compiler.
