# Forth From a 2040-Byte Seed

A tutorial book that teaches Forth, and the art of bootstrap, by
reading — and extending — the source of this repository.

## Two stories, equal weight

This book tells two stories braided together.

**The Forth story.**  Forth is the language programmers built when
computers had 4 KB of RAM.  It has no syntax — only whitespace-separated
tokens — and almost no semantics beyond a data stack and a dictionary
of definitions.  From that minimalism comes an unusual property: *the
compiler is itself a program written in the language*, extensible at
the level of parsing, compilation, and immediate execution.

**The bootstrap story.**  The codebase reaches from 2,040 hand-coded
bytes (`000-seed.hex0`) all the way to a C-subset compiler whose M1
output is byte-identical to M2-Planet built with GCC.  That last
property — byte-identity against a reference — is what makes the chain
auditable and useful for projects like the Guix Full Source Bootstrap.

Neither story works without the other.  The Forth language is what
makes a 2,040-byte seed expressive enough to host a compiler; the
bootstrap chain is what gives the Forth itself ground to stand on.

A secondary story — that this codebase was synthesised through human
collaboration with an ensemble of large language models — is told in
`AI_STRATEGIES.md` and the Prologue's closing note.  It is the *how*,
not the *what*.

## Audience

You write code already.  You know what a stack is, what `malloc` does,
and roughly what an ELF executable is.  You have never written Forth
(or you tried once, found the `: ;` syntax baffling, and bounced off).

## What you will be able to do at the end

- Read `010-lib.fth` line by line and explain how each definition
  derives from the 32 hand-encoded primitives.
- Read `000-seed.hex0` byte by byte and explain why each x86-64
  instruction is there.
- Write your own immediate words that emit machine code.
- Follow `100-cc-expr.fth` and `110-cc-decl.fth` and add a new operator
  or statement to the C compiler.
- Rebuild the bootstrap and verify byte-identical M1 output against
  the GCC-built M2-Planet reference.

## Shape of the book

Three parts plus a Prologue and four appendices.  **Chapter order is
source order.**  Every fenced code block tagged `file=<path>` is the
canonical source for that file, and the blocks appear in the book in
the same order they appear in the file.  When the strict tangle check
passes, the book *is* the codebase.

### Prologue

- [0. Two thousand and forty bytes](00-prologue.md) — the journey, the
  stakes, how to read.

### Part I — Forth from the lib up

Twelve chapters walking `010-lib.fth` in source order.  The seed's
primitives are black boxes for now; you can run every example in
gforth via `book/playground.fth`.

Status legend: ✏️ stub awaiting prose · 📝 prose in progress · ✅ done.

| # | Chapter | Covers | Status |
|---|---|---|---|
| 1 | [Stacks and words](01-stacks-and-words.md) | RPN, stack-effect comments, the dictionary concept; `010-lib.fth` file header | 📝 |
| 2 | [Code emission and the HERE pointer](02-code-emission-and-here.md) | `here-addr`, `c,` | ✏️ |
| 3 | [Logic from one primitive](03-logic-from-nand.md) | `and`, `or` | ✏️ |
| 4 | [The return stack: `over` and subtract](04-return-stack-over-subtract.md) | `over`, `-` | ✏️ |
| 5 | [Talking to Linux: syscall6 wrappers](05-syscalls.md) | `open`, `read`, `write`, `close`, `die` | ✏️ |
| 6 | [Character classification](06-character-classification.md) | `digit?`, `alpha?`, `space?` | ✏️ |
| 7 | [Comparisons from unsigned division](07-comparisons-from-division.md) | `=`, `<>`, `<`, `>`, `<=`, `>=`, `neg-flag`, `2^63` | ✏️ |
| 8 | [Stack shufflers](08-stack-shufflers.md) | `nip`, `rot`, `2dup`, `2drop` | ✏️ |
| 9 | [Memory updates and cell writers](09-memory-and-cell-writers.md) | `+!`, `-!`, `,4`, `,8` | ✏️ |
| 10 | [Immediacy and constants](10-immediacy-and-constants.md) | `immediate`, `constant` | ✏️ |
| 11 | [Control-flow combinators *(climax)*](11-control-flow-combinators.md) | `branch-xt`, `0branch-xt`, `comma-call`, `if,`, `then,`, `else,`, `begin,`, `while,`, `repeat,` | ✏️ |
| 12 | [`allot`, `create`, `variable`, `bytes-eq`](12-defining-words-and-bytes-eq.md) | the rest of `010-lib.fth` | ✏️ |

### Part II — The seed VM

Eight chapters opening the black box.  `000-seed.hex0` is 752 lines of
annotated hex; chapters use noweb-style named chunks so the seed is
taught by topic rather than by ELF offset.

| # | Chapter | Covers | Status |
|---|---|---|---|
| 13 | [The ELF and the entry point](13-elf-and-entry.md) | header, program header, `_start`, sysvar init | ✏️ |
| 14 | [Stack primitives in machine code](14-stack-primitives.md) | `dup`, `drop`, `swap`, `>r`, `r>`, `@`, `!`, `c@`, `c!` | ✏️ |
| 15 | [Arithmetic, logic, comparison](15-arithmetic-and-logic.md) | `+`, `nand`, `0=`, `/`, `*` | ✏️ |
| 16 | [I/O: `emit`, `key`, `syscall6`](16-io-emit-key-syscall6.md) | the I/O scratch page; `read_word` | ✏️ |
| 17 | [The dictionary](17-the-dictionary.md) | header layout, `find`, `here`, `,`, `latest`, `'`, `execute` | ✏️ |
| 18 | [The colon compiler](18-the-colon-compiler.md) | `:`, `;`, `lit` | ✏️ |
| 19 | [Branches and inline cells](19-branches-and-inline-cells.md) | `branch`, `0branch` | ✏️ |
| 20 | [The number parser and REPL](20-number-parser-and-repl.md) | `parse_decimal`, `STATE`, the main loop, the `?` miss path | ✏️ |

### Part III — A C compiler in Forth

Twelve chapters walking `020-cc-*.fth` through `120-cc-main.fth`.  Each
big file (`040`, `050`, `090`, `100`, `110`) is split across multiple
chapters so the reader sees one coherent idea per chapter.

| # | Chapter | Covers | Status |
|---|---|---|---|
| 21 | [Arena and I/O buffers](21-arena-and-io-buffers.md) | `020-cc-arena.fth`, `030-cc-io.fth` | ✏️ |
| 22 | [The preprocessor](22-the-preprocessor.md) | `040-cc-prep.fth` | ✏️ |
| 23 | [The lexer](23-the-lexer.md) | `050-cc-lex.fth` | ✏️ |
| 24 | [Types and symbols](24-types-and-symbols.md) | `060-cc-types.fth`, `070-cc-sym.fth` | ✏️ |
| 25 | [ELF emission and codegen, part 1](25-elf-and-codegen-part-1.md) | `080-cc-elf.fth`, `090-cc-emit.fth` (instructions) | ✏️ |
| 26 | [Codegen, part 2: calls and locals](26-codegen-part-2.md) | the rest of `090-cc-emit.fth` | ✏️ |
| 27 | [Expressions, part 1: precedence climbing](27-expressions-part-1.md) | `100-cc-expr.fth` (operators) | ✏️ |
| 28 | [Expressions, part 2: assignment, postfix, struct access](28-expressions-part-2.md) | the rest of `100-cc-expr.fth` | ✏️ |
| 29 | [Declarations: types and globals](29-declarations-types-globals.md) | `110-cc-decl.fth` (part 1) | ✏️ |
| 30 | [Statements: if, while, for, return](30-statements-if-while-for-return.md) | `110-cc-decl.fth` (part 2) | ✏️ |
| 31 | [Functions: parameters, locals, scope](31-functions-and-scope.md) | `110-cc-decl.fth` (part 3) | ✏️ |
| 32 | [End to end: main and the bootstrap chain](32-main-and-bootstrap-chain.md) | `120-cc-main.fth` + `tests/cc/` | ✏️ |

### Appendices

- **A.** The 32 seed primitives — one-line reference card.
- **B.** The memory map.
- **C.** Reproducibility: the full hex0 → seed → M2-Planet chain.
- **D.** Exercises with worked solutions.

## How to read this book

Open the book in one editor pane and the file under discussion in
another.  The book exists to make the source readable; it is not a
substitute for it.

Read Part I with `gforth` installed and the shim at
[`book/playground.fth`](playground.fth) loaded.  You do not need to
build the seed itself until Part II, when we start reading the hex.

## The book is literate

Every fenced code block tagged `file=<path>` is the canonical source
for that file.  Run

```sh
tools/tangle.sh extract /tmp/out
```

to write those blocks (concatenated in chapter order, with `<<name>>`
chunk references expanded for `000-seed.hex0`) into
`/tmp/out/010-lib.fth`, `/tmp/out/000-seed.hex0`, and so on.

`tools/tangle.sh verify` is wired into `./test.sh` and checks that
every quoted block appears, in order, in the matching source file.
That is the cheap consistency check that runs on every test run.

The full literate-program claim — *the book compiles* — is

```sh
tools/tangle.sh verify --strict
```

which passes only when the tangled files are byte-identical to the
checked-in source.  Until every chapter is written, strict mode fails
(and shows you which spans of source still need prose).  Coverage
progress is visible with

```sh
tools/tangle.sh status
```

Migration is per-file: while a file is partly covered, the standalone
copy in the repository root remains the source of record.  Once a file
is fully covered and `verify --strict` passes for it, we delete the
standalone copy and let `tangle.sh extract` produce it before the
build.  When every file has flipped, the book *is* the codebase.
