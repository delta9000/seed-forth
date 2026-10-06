# A C Compiler in Forth

A source program and an executable are different kinds of object. This book
follows one small program, `tri.c`, through the representations between them:
owned byte spans, expanded source, tokens, type and name records, instructions,
and a finished image. At each boundary, ask what must be preserved and who
keeps the required state alive.

Start with [Compiler entry and profile](chapters/01-compiler-entry-and-profile.md).
It teaches the C syntax needed for the recurring example and provides a short
Forth diagnostic with targeted refreshers. You do not need to memorize the
first volume's machine-code audit before entering here.

## Available teaching route

1. [Compiler entry and profile](chapters/01-compiler-entry-and-profile.md):
   derive the triangle, separate builder and generated program, and choose the
   exact profile before making a size or calling-convention claim
2. [Buffers, arenas, and failure ownership](chapters/02-buffers-arenas-and-failure.md):
   trace byte spans, cursors, capacity, lifetime, allocation, emission and the
   limits of I/O and error handling
3. [Preprocessing regions and includes](chapters/03-preprocessing-regions-and-includes.md):
   preserve input ownership while nested files contribute to one output sink
4. [Macro expansion and rescanning](chapters/04-macro-expansion-and-rescanning.md):
   preserve definitions and arguments while replacement text is scanned again
5. [Conditional preprocessing and profile extensions](chapters/05-conditionals-and-profile-extensions.md):
   select active groups and distinguish physical, logical and diagnostic locations

These five chapters provide twenty-six exercises and separate feedback
companions. Try a
prediction, use a hint when a step is missing, then attempt a changed case
without copying the worked answer. The purpose is to explain a mechanism,
not to memorize the order of source filenames.

The [first mixed return check](practice/return-check.md) revisits all three
chapters without giving each problem a chapter title as its cue.

The [second mixed check](practice/return-check-2.md) revisits replacement
ownership, conditional state and source identity.

The next unit opens tokens and reversible lookahead. The
[coverage map](../COVERAGE.md#volume-2-a-c-compiler-in-forth) assigns the later
lexer, type, parser, emitter, assembler and bootstrap units. Planned
units are not chapters that already exist.

## Profile and evidence

The first route uses the pinned legacy direct-ELF compiler: the Forth builder
emits an executable image directly. Optional direct TinyCC and System V routes
have their own storage, calling, preprocessing and runtime contracts. Loading
their definitions does not silently make the default path equivalent to them.
The [entry chapter](chapters/01-compiler-entry-and-profile.md#name-the-compiler-profile)
provides the comparison before the distinction matters in a trace.

All implementation claims use the [edition pin](../EDITION.md). The chapters
contain inspected source and paper derivations, not transcripts of newly run
compilers. The new examples and fresh-reader setup remain unexecuted; there
has been no real-reader validation. Existing repository CI has its own
[validation record](../VALIDATION.md) and does not execute these exercises.

The eventual volume outcome includes the legacy compiler/M2-Planet comparison,
the Forth assembler handoff and a separately identified TinyCC extension.
Those closing units are still planned. A current direct-GCC-to-Linux outcome
requires its own evidence in the later kernel volume.

## Find the implementation

The [source map](SOURCE-MAP.md) connects explanations to exact definitions and
immutable source spans. It is a reading aid, not a second source authority.
The original implementation and literate `book/` tree are unchanged; this
teaching edition is not input to their tangler.
