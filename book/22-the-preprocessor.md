# Chapter 22 — The Preprocessor

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- enumerate the preprocessor directives this compiler supports
  (`#include`, `#define`, and the conditional set — confirm by
  grepping `040-cc-prep.fth`);
- explain the macro storage layout and the name-comparison hook
  into `bytes-eq`;
- read the `#include` path search and explain why the compiler
  doesn't need angle-bracket vs quote-bracket distinction (or does
  it? — check while writing).

## Source coverage

`040-cc-prep.fth` (630 lines) — entire file.

## Concepts introduced

- **The preprocessor as a source rewriter.**  Reads `cc-src-buf`,
  produces a rewritten source in the same buffer (or a second one)
  with macros expanded and `#include`d files inlined.
- **Macro table** — parallel arrays of name-pointer / name-length /
  body-pointer / body-length, looked up by `bytes-eq` (Ch 12).
- **`#include` path resolution.**  This compiler exists to bootstrap
  M2-Planet, whose includes have a known layout — confirm what's
  supported (relative paths, search prefixes) when writing.

## Concepts carried in

- `cc-peek-char`, `cc-next-char` (Ch 21).
- `cc-alloc` (Ch 21).
- `bytes-eq` (Ch 12).
- `digit?`, `alpha?`, `space?` (Ch 6).

## Concepts deferred

- Token emission to the lexer — Ch 23.

## Section plan

1. **What this preprocessor does (and doesn't).**  Scan
   `040-cc-prep.fth`'s top comment to enumerate exactly which
   directives are handled.  Note that M2-Planet's own headers
   restrict what we need to support.
2. **Macro storage.**  Walk the `create cc-macro-name` / `cc-macro-
   body` / counter trio; explain why parallel arrays here instead
   of a record-of-pointers (memory locality + simpler `bytes-eq`).
3. **`#define` parsing.**  Read the directive parser: consume `#`,
   then `define`, then identifier, then rest-of-line as body.
   Trim trailing whitespace; store.
4. **Macro lookup and expansion.**  When a non-keyword identifier
   is seen at expansion time, `bytes-eq` against every macro name;
   on hit, splice in the body and continue.
5. **`#include` resolution.**  Read the path; locate the file;
   recursively load into the source buffer.  Recursion depth limit?
   Cycle detection?  Confirm when writing.
6. **Edge cases.**  Multi-line macros (does this preprocessor
   support backslash-newline?); macro arguments (does it support
   function-style macros?); `#undef`; `#if`/`#ifdef`.  Tick each
   when reading the source.

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=040-cc-prep.fth
\   <body of 040-cc-prep.fth>
\   ```
```

## Try it

```sh
./build.sh
# Feed a C source with #include / #define through the preprocessor
# in isolation (if there's a test harness) or end-to-end via
# tests/cc/stage-a-check.sh.
tests/cc/stage-a-check.sh
```

Read `tests/cc/G*.c` and `tests/cc/M*.c` — small cases that
document what the preprocessor handles.

## Exercises

1. M2-Planet uses some preprocessor features; which ones does this
   compiler support?  Make a table by grepping the file.

2. Add `#undef NAME` if it's not there.  How many lines?  What's
   the cost in code size?

3. Function-style macros (`#define FOO(x) ((x)+1)`) are common.
   Confirm whether this compiler supports them by trying a test
   case.

4. `#include` cycles would loop forever.  Read the code and find
   the (probably missing) cycle check.  Construct a test case that
   demonstrates the loop, then patch.

## Takeaways

- The preprocessor is a separate pass that rewrites source.  The
  lexer (Ch 23) reads the rewritten source, not the original.
- Macro storage is parallel arrays + `bytes-eq` lookup — the same
  technique used for the symbol table (Ch 24).
- `#include` recursion is handled by re-entering the file-loading
  routine; the source buffer grows in place.

Next: Chapter 23 — The Lexer.
