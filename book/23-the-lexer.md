# Chapter 23 — The Lexer

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- enumerate the token kinds this lexer emits (`KW_*`, `ID`, `PUNCT`,
  `NUM`, `STR`, `CHR`, comments) and the values associated with each;
- read the keyword table and explain why it sits in a parallel array
  rather than the symbol table;
- read the lexer state machine and trace a single token's emission
  from `cc-next-char` through to the parser's input slot.

## Source coverage

`050-cc-lex.fth` (642 lines) — entire file.

## Concepts introduced

- **Token records.**  Each token has a kind, a value (numeric or
  string pointer), and a source location for error messages.
- **Keyword recognition.**  After lexing an identifier, look it up
  in a keyword table; on hit, emit `KW_*` instead of `ID`.
- **String / char literals.**  Escape sequences (`\n`, `\t`, `\\`,
  `\"`, `\0`).  Storage in the source-string pool.
- **Comments.**  `/* ... */` and `// ...`; both skipped.

## Concepts carried in

- `cc-peek-char`, `cc-next-char`, `cc-src-line` (Ch 21).
- `digit?`, `alpha?`, `space?` (Ch 6).
- `bytes-eq` (Ch 12) — for keyword lookup.
- `cc-alloc` (Ch 21).

## Concepts deferred

- How the parser (`100-cc-expr.fth`, `110-cc-decl.fth`) consumes
  these tokens — Chs 27–31.

## Section plan

1. **The token kinds.**  Pull the `[lit] N constant TK_*` list from
   the top of `050-cc-lex.fth` and tabulate.  ~15–20 kinds.
2. **The reader interface.**  `cc-lex-init`, `cc-lex-next` (advance
   to next token), `cc-lex-kind`, `cc-lex-val`, `cc-lex-line` —
   the parser's only view into the lexer.
3. **Identifiers and keywords.**  Lex an identifier (alpha then
   alpha-digit-underscore); on completion, check the keyword
   table; emit `KW_*` or `ID`.
4. **Numeric literals.**  Decimal, hex (`0x`), octal (`0`).  Each
   reads digits in its base, accumulates, emits `NUM`.
5. **Strings, chars, escapes.**  Read until closing `"` or `'`;
   process backslash escapes; copy to the string pool; emit `STR`
   or `CHR`.
6. **Punctuation.**  Each operator is its own token kind (`'+'`,
   `'-'`, `'*'`, `'=='`, `'<<'`, etc.).  Multi-char punctuators
   are handled by lookahead.
7. **Comments.**  Skip `/*...*/` (track nested? probably not) and
   `//...\n` without emitting any token.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=050-cc-lex.fth
\   <body of 050-cc-lex.fth>
\   ```
```

## Try it

```sh
./build.sh
./test.sh    # exercises the lexer via test-050-cc-lex.fth
             # (look for kw/id/punct/num/str/chr/comment/escape assertions)
```

Read `test-050-cc-lex.fth` carefully — it documents every token
kind by example.

## Exercises

1. Tabulate every keyword.  Compare with the C90 keyword list —
   which are missing?  Which are M2-Planet-only?

2. The compiler doesn't support multi-character constants
   (`'ab'` etc.).  Confirm by trying one and observing the failure.

3. Add hex-float literals (`0x1.0p0`).  How many lines?  Why
   doesn't M2-Planet need them?

4. The string pool grows monotonically.  Could the lexer dedupe
   identical string literals?  What would the cost be?

## Takeaways

- The lexer is the second-largest file in the compiler (642 lines)
  because punctuation, escapes, and numeric bases all need attention.
- Keywords are recognised post-hoc: lex as identifier, then look up.
  Same name-comparison technique as the symbol table.
- The parser sees a stream of `(kind, value, line)` triples and
  knows nothing about source characters.

Next: Chapter 24 — Types and Symbols.
