# Seed Forth teaching books

This teaching edition now plans one main capability route toward direct GCC:
a small Forth result, a simple C executable, independently compiled objects
joined into a program, GCC with its source-built output tools, then hosted
closure and a bounded rebuild comparison. The [hybrid narrative](HYBRID-NARRATIVE.md)
and [unit-by-unit route map](narrative-map.csv) distinguish the first sessions,
supplied contracts, implementation depth and alternate routes. H1–H5 are
learning milestones. The H1/H2 paper entrance and bounded G01 first story
are drafted; operational setup and observed fixture runs remain pending.

Begin with [Two small results](FIRST-RESULTS.md): distinguish a Forth stack
value, a requested output byte and a C process result. Its [four entrance
prompts and feedback](practice/first-results-solutions.md) lead into S1 or
C19's fuller derivation. Then continue to [G01: a program from two files](gcc-toolchain/chapters/01-a-program-from-two-files.md)
to follow an unresolved call through objects, linking and real startup.
G01's bounded source/practice and model-assisted prerequisite reviews are complete; its fixture and
command card remain unexecuted.

The complete [Seed and Forth](seed-forth/README.md) route remains available,
including all 1,772 original file bytes and its separate audit capstone.
Finishing that audit is its own objective, rather than a gate before the
first C result. C19's 556-byte layout and G01's illustrative relocation are
paper derivations, not measured artifacts.

The [C-compiler volume](c-compiler/README.md) now has twenty-two paper chapters,
from an independent entry bridge through preprocessing, representations,
emission/runtime, expressions/declarations, statements, function frames and
translation-unit/process entry, the bounded Stage-A recipe and evidence,
then the complete standalone Forth assembler and its source-built-tool handoff.
Its 167 main exercises have separate feedback; six mixed checks add 24 questions.
The edition now has 269 chapter exercises: 95 seed, 167 C and seven G01.
The four H1/H2 entrance prompts are counted separately. The earlier 262
chapter exercises remain intact. C19's full technical/practice manuscript review is complete; C16–C18's
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

M2/M1/hex2, pnut and direct TinyCC remain distinct alternate tracks. Their
executable chains are not compulsory ancestors of direct GCC. A short C20/C22
case study can illustrate replacing an assembly service without making its
whole route required reading. Shared LP64 declarations and initializer
machinery still belong to the direct-profile learning contract; optional
TinyCC execution does not make those implementation mechanisms optional.

The edition is a draft, not a complete replacement for the original book.
The [coverage map](COVERAGE.md) accounts for every original numbered chapter
and appendix, including material not rewritten yet.

## Books and entry points

| Book | Intended completed outcome | Current state |
|---|---|---|
| [Seed and Forth](seed-forth/README.md) | Build useful Forth words, then audit how the seed implements them | Complete paper route drafted; all seed bytes and library definitions covered; execution and reader validation pending |
| [A C compiler in Forth](c-compiler/README.md) | Follow a small C program through preprocessing, tokens, types, code generation and an explicit bootstrap check | Default compiler, Stage-A recipe/evidence and complete bounded assembler/handoff drafted through C22; source/practice reviewed; native/TinyCC and broader bootstrap closure remain planned |
| [From compiler to toolchain](gcc-toolchain/README.md) | Follow the main objects/System V/link/runtime → generators/GCC/output tools → hosted/rebuild route | G01 bounded profile entrance drafted; source/practice and model-assisted prerequisite reviews complete; G02–G25 remain planned, including complete object/ABI/link/runtime mechanisms |
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

- [Two small results](FIRST-RESULTS.md) supplies the H1/H2 paper entrance
- [A program from two files](gcc-toolchain/chapters/01-a-program-from-two-files.md)
  supplies G01's bounded object/profile story and [seven feedback sets](gcc-toolchain/practice/01-solutions.md)
- [Edition and evidence](EDITION.md) pins the exact source and distinguishes
  source inspection, hand-derived traces and observed runs
- [Hybrid narrative](HYBRID-NARRATIVE.md) and [route data](narrative-map.csv)
  show the five milestones, supplied first-session contracts and depth/alternate routes
- [Learning path](LEARNING-PATH.md) shows full-depth prerequisites, outcomes
  and explicit interfaces whose machinery is opened later
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
checks cover 71 pinned project files;
none of these counts is a claim of whole-bootstrap implementation coverage.
G01 adds three inspected source blobs and a bounded teaching story, not a new
complete-definition or whole-module inventory.

The new teaching examples have not been executed; repository CI results,
where available, cover their separately named canonical checks.
The worked states are derived from the stated contracts and inspected source.
Changing reading order supplies no new execution, setup or learner evidence.
Production tools, temporarily supplied teaching components, comparison controls
and optional executable routes must be identified separately at each milestone.
An expert review or a document checker cannot establish how well a new reader
will learn from them; that needs reader attempts and revision.
