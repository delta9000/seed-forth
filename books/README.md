# Seed Forth teaching books

This is the learning-first teaching edition of Seed Forth. Start with
[Seed and Forth](seed-forth/README.md): its first-volume paper route is drafted,
with an entry guide, motivation chapter, nineteen worked chapters and a
compact reference. It takes you from stack contracts through the library
and all 1,772 bytes of the executable, then assembles the ideas in a
whole-seed capstone.
Each mechanism has a source-pinned trace and separate practice feedback.

The [C-compiler volume](c-compiler/README.md) now has twenty-two paper chapters,
from an independent entry bridge through preprocessing, representations,
emission/runtime, expressions/declarations, statements, function frames and
translation-unit/process entry, the bounded Stage-A recipe and evidence,
then the complete standalone Forth assembler and its source-built-tool handoff.
Its 167 main exercises have separate feedback; six mixed checks add 24 questions.
The edition has 262 main exercises including
the seed volume. C19's full technical/practice manuscript review is complete; C16–C18's
reported technical, practice and first-reading reviews are complete. C20 has
complete source/recipe coverage; its source/practice review and final readback are complete.
C21/C22 are also source/practice-reviewed paper drafts. New example execution,
rendered-layout review and actual-reader learning remain unverified.

C19 derives a small program's 556-byte output-buffer layout and predicted exit
path. [C20](c-compiler/chapters/20-complete-compiler-and-stage-a.md) explains
the next producer executions and exact M1 comparison, with a separately
attributed remote result. [C21](c-compiler/chapters/21-assembler-input-and-expansion.md)
and [C22](c-compiler/chapters/22-two-pass-assembly-and-bootstrap-handoff.md)
now open expansion, two-pass assembly and the exact source-built-tool
comparisons. Native/TinyCC work remains C23/C24; broader bootstrap lineages
keep their own unfinished reference obligations. The earlier reviewed C01–C15 checkpoint and
[continuation-draft notes](c-compiler/DRAFTS.md) retain their historical scope.

The edition is a draft, not a complete replacement for the original book.
The [coverage map](COVERAGE.md) accounts for every original numbered chapter
and appendix, including material not rewritten yet.

## Books and entry points

| Book | Intended completed outcome | Current state |
|---|---|---|
| [Seed and Forth](seed-forth/README.md) | Build useful Forth words, then audit how the seed implements them | Complete paper route drafted; all seed bytes and library definitions covered; execution and reader validation pending |
| [A C compiler in Forth](c-compiler/README.md) | Follow a small C program through preprocessing, tokens, types, code generation and an explicit bootstrap check | Default compiler, Stage-A recipe/evidence and complete bounded assembler/handoff drafted through C22; source/practice reviewed; native/TinyCC and broader bootstrap closure remain planned |
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

The source maps account for 576 colon definitions across fourteen compiler/assembler
files, plus the separate preprocessor-region inventory. The control/function/
program ledger distinguishes 160 declarations from ten top-level forms;
coverage does not mean those forms were executed here. The [pipeline
map](c-compiler/pipeline-map.csv) separately covers 33 regions/273 lines in five
complete shell scripts. The [assembler ledger](c-compiler/assembler-regions.csv)
adds all 785 lines in 42 regions, 99 declarations and two initialization
forms; its 50 colon definitions are included in the 576 total. Source-blob
checks cover 59 pinned project files;
none of these counts is a claim of whole-bootstrap implementation coverage.

The new teaching examples have not been executed; repository CI results,
where available, cover their separately named canonical checks.
The worked states are derived from the stated contracts and inspected source.
An expert review or a document checker cannot establish how well a new reader
will learn from them; that needs reader attempts and revision.
