# Seed Forth teaching books

This is the learning-first teaching edition of Seed Forth. Start with
[Seed and Forth](seed-forth/README.md): its first-volume paper route is drafted,
with an entry guide, motivation chapter, nineteen worked chapters and a
compact reference. It takes you from stack contracts through the library
and all 1,772 bytes of the executable, then assembles the ideas in a
whole-seed capstone.
Each mechanism has a source-pinned trace and separate practice feedback.

The [C-compiler volume](c-compiler/README.md) also has its first fifteen teaching
chapters: an independent entry bridge, storage/ownership, preprocessing,
tokens/types/names, executable bytes, deferred addresses and the bounded
legacy runtime, places/values, expressions and declarations. Statement/function
integration and bootstrap-closure units remain planned.

The edition is a draft, not a complete replacement for the original book.
The [coverage map](COVERAGE.md) accounts for every original numbered chapter
and appendix, including material not rewritten yet.

## Books and entry points

| Book | Intended completed outcome | Current state |
|---|---|---|
| [Seed and Forth](seed-forth/README.md) | Build useful Forth words, then audit how the seed implements them | Complete paper route drafted; all seed bytes and library definitions covered; execution and reader validation pending |
| [A C compiler in Forth](c-compiler/README.md) | Follow a small C program through preprocessing, tokens, types, code generation and an explicit bootstrap check | Infrastructure, preprocessing, representations, emission/runtime, expressions and declarations drafted; statement/function/closure units remain planned |
| From compiler to toolchain | Explain objects, linking, runtime contracts and the direct GCC rebuild comparisons | Planned; existing chapters 35–49 and the newer driver documentation remain the source material |
| Kernels and Linux | Explain the toolchain-to-kernel transition and a precisely observed boot outcome | Planned; the current direct-GCC-to-Linux route needs its own evidence |

The four-book division is an editorial plan. It can change as the dependency
map and first-reader attempts reveal better boundaries. Each completed book
should have a usable entry contract and a finished capability, rather than
requiring readers to master all previous volumes before doing anything.

## Teaching prose and implementation

The new `books/` tree is explanatory prose with selected, source-pinned
excerpts. It is not input to the existing literate-source tangler. The original
`book/`, root source files, build scripts and `book.toml` remain unchanged.
Plain code fences in this edition must not carry `file=` or `chunk=` metadata.

This separation lets a teaching sequence follow prerequisites while the source
keeps its operational order. Small source annotations can later point to stable
chapter sections; they should explain invariants and contracts without making
the implementation depend on a manuscript build. Replacing the original
canonical-source arrangement is a separate migration, not part of these foundation
units.

## Evidence and use

- [Edition and evidence](EDITION.md) pins the exact source and distinguishes
  source inspection, hand-derived traces and observed runs
- [Learning path](LEARNING-PATH.md) shows prerequisites, outcomes and explicit
  interfaces whose machinery is opened later
- [Validation record](VALIDATION.md) says what was checked and what remains
  unverified
- [Coverage data](coverage.csv) makes remaining migration work sortable
- [Seed byte audit](seed-forth/AUDIT.md) assigns every file byte and shows
  which regions are explained so far

The new teaching examples have not been executed; repository CI results,
where available, cover their separately named canonical checks.
The worked states are derived from the stated contracts and inspected source.
An expert review or a document checker cannot establish how well a new reader
will learn from them; that needs reader attempts and revision.
