# Forth From a 2040-Byte Seed

2,040 bytes of hand-encoded x86-64 ELF, a Forth that those bytes
boot into, and about 7,400 lines of Forth code that build a C compiler
whose `.M1` output is byte-identical to the output from GCC-built
M2-Planet.
This book is the manual for all of it.

Two pages set the scene before Chapter 1:

- **[Where this fits in the bootstrap ecosystem](where-this-fits.md)**
  if you want to know how this project plugs into the
  Bootstrappable / Full Source Bootstrap chain that Guix consumes.
- **[Prologue: Two thousand and forty bytes](00-prologue.md)** for
  the language and the journey; why Forth makes a 2,040-byte seed
  possible at all.

## Audience

You write code already.  You know what a stack is, what `malloc` does,
and roughly what an ELF executable is.  You have never written Forth
(or you tried once, found the `: ;` syntax baffling, and bounced off).

You do **not** need to know x86-64 assembly, the ELF format in
detail, the Linux syscall ABI, the Forth standard library, or
anything about bootstrap chains.  The book introduces each of
these as it needs them, in the order it needs them.

## Before you start

The seed is hand-encoded x86-64 ELF, so the codebase runs natively
only on **Linux x86-64**.  Apple Silicon, ARM Linux, and Windows
readers will need a Linux/amd64 VM, container, or QEMU emulation;
the book is the same on every platform but `./build.sh` and
`./test.sh` need an amd64 Linux kernel underneath.

What you'll want installed:

- **bash** and a modern **POSIX coreutils**.  The build is shell
  scripts plus the vendored hex0 assembler; no make, no autoconf.
- **gforth** for Part I.  The playground at
  [`book/playground.fth`](playground.fth) loads under any recent
  gforth (0.7+; Debian, Fedora, Homebrew all ship a workable
  version).  You don't need to build the seed until Part II.
- **git** to clone the repo with its `vendor/` submodules
  (stage0-posix's `hex0-seed` is checked in there).
- **A C compiler** (gcc or clang) **only** if you want to run the
  Stage-A check (Appendix C); the book itself never invokes it.

Disk budget: ~30 MiB for the repo plus vendored stage0-posix /
M2-Planet / mescc-tools.  Memory: a few MiB at runtime; the C
compiler reserves a 256 MiB heap but only touches what it uses.

## Shape of the book

Three parts plus a prologue and seven appendices.  Chapter order is
source order.  Every fenced code block tagged `file=<path>` is the
canonical source for that file, and the blocks appear in the book
in the same order they appear in the file.  When the strict tangle
check passes, the book *is* the codebase.

### Prologue

- [0. Two thousand and forty bytes](00-prologue.md)

### Part I — Forth from the lib up

Twelve chapters walking `010-lib.fth` in source order.  The seed's
primitives are black boxes for now; you can run every example in
gforth via `book/playground.fth`.

| # | Chapter | Covers |
|---|---|---|
| 1 | [Stacks and words](01-stacks-and-words.md) | RPN, stack-effect comments, the dictionary concept; `010-lib.fth` file header |
| 2 | [Code emission and the HERE pointer](02-code-emission-and-here.md) | `here-addr`, `c,` |
| 3 | [Logic from one primitive](03-logic-from-nand.md) | `and`, `or` |
| 4 | [The return stack: `over` and subtract](04-return-stack-over-subtract.md) | `over`, `-` |
| 5 | [Talking to Linux: syscall6 wrappers](05-syscalls.md) | `open`, `read`, `write`, `close`, `die` |
| 6 | [Character classification](06-character-classification.md) | `digit?`, `alpha?`, `space?` |
| 7 | [Comparisons from unsigned division](07-comparisons-from-division.md) | `=`, `<>`, `<`, `>`, `<=`, `>=`, `neg-flag`, `2^63` |
| 8 | [Stack shufflers](08-stack-shufflers.md) | `nip`, `rot`, `2dup`, `2drop` |
| 9 | [Memory updates and cell writers](09-memory-and-cell-writers.md) | `+!`, `-!`, `,4`, `,8` |
| 10 | [Immediacy and constants](10-immediacy-and-constants.md) | `immediate`, `constant` |
| 11 | [Control-flow combinators *(climax)*](11-control-flow-combinators.md) | `branch-xt`, `0branch-xt`, `comma-call`, `if,`, `then,`, `else,`, `begin,`, `while,`, `repeat,` |
| 12 | [`allot`, `create`, `variable`, `bytes-eq`](12-defining-words-and-bytes-eq.md) | the rest of `010-lib.fth` |

### Part II — The seed VM

Eight chapters opening the black box.  `000-seed.hex0` is 752 lines of
annotated hex; chapters use noweb-style named chunks so the seed is
taught by topic rather than by ELF offset.

| # | Chapter | Covers |
|---|---|---|
| 13 | [The ELF and the entry point](13-elf-and-entry.md) | header, program header, `_start`, sysvar init |
| 14 | [Stack primitives in machine code](14-stack-primitives.md) | `dup`, `drop`, `swap`, `>r`, `r>`, `@`, `!`, `c@`, `c!` |
| 15 | [Arithmetic, logic, comparison](15-arithmetic-and-logic.md) | `+`, `nand`, `0=`, `/`, `*` |
| 16 | [I/O: `emit`, `key`, `syscall6`](16-io-emit-key-syscall6.md) | the I/O scratch page; `read_word` |
| 17 | [The dictionary](17-the-dictionary.md) | header layout, `find`, `here`, `,`, `latest`, `'`, `execute` |
| 18 | [The colon compiler](18-the-colon-compiler.md) | `:`, `;`, `lit` |
| 19 | [Branches and inline cells](19-branches-and-inline-cells.md) | `branch`, `0branch` |
| 20 | [The number parser and REPL](20-number-parser-and-repl.md) | `parse_decimal`, `STATE`, the main loop, the `?` miss path |

### Part III — A C compiler in Forth

Twelve chapters walking `020-cc-*.fth` through `120-cc-main.fth`.  Each
big file (`040`, `050`, `090`, `100`, `110`) is split across multiple
chapters so the reader sees one coherent idea per chapter.

| # | Chapter | Covers |
|---|---|---|
| 21 | [Arena and I/O buffers](21-arena-and-io-buffers.md) | `020-cc-arena.fth`, `030-cc-io.fth` |
| 22 | [The preprocessor](22-the-preprocessor.md) | `040-cc-prep.fth` |
| 23 | [The lexer](23-the-lexer.md) | `050-cc-lex.fth` |
| 24 | [Types and symbols](24-types-and-symbols.md) | `060-cc-types.fth`, `070-cc-sym.fth` |
| 25 | [ELF emission and codegen, part 1](25-elf-and-codegen-part-1.md) | `080-cc-elf.fth`, `090-cc-emit.fth` (instructions) |
| 26 | [Codegen, part 2: calls and locals](26-codegen-part-2.md) | the rest of `090-cc-emit.fth` |
| 27 | [Expressions, part 1: precedence climbing](27-expressions-part-1.md) | `100-cc-expr.fth` (operators) |
| 28 | [Expressions, part 2: assignment, postfix, struct access](28-expressions-part-2.md) | the rest of `100-cc-expr.fth` |
| 29 | [Declarations: types and globals](29-declarations-types-globals.md) | `110-cc-decl.fth` (part 1) |
| 30 | [Statements: if, while, for, return](30-statements-if-while-for-return.md) | `110-cc-decl.fth` (part 2) |
| 31 | [Functions: parameters, locals, scope](31-functions-and-scope.md) | `110-cc-decl.fth` (part 3) |
| 32 | [End to end: main and the bootstrap chain](32-main-and-bootstrap-chain.md) | `120-cc-main.fth` + `tests/cc/` |

### Appendices

- **A.** [The 32 seed primitives](A1-32-seed-primitives.md) — one-line reference card.
- **B.** [The memory map](A2-memory-map.md).
- **C.** [Reproducibility: the full hex0 → seed → M2-Planet chain](A3-reproducibility-chain.md).
- **D.** [Three worked exercises, one per Part](A4-worked-exercises.md).
- **E.** [Further reading](A5-further-reading.md) — Forth, compilers, bootstrap, ELF/x86-64.
- **F.** [The C subset](A6-c-subset.md) — types, operators, statements, and what is *not* supported.
- **G.** [Compiler exit codes](A7-error-codes.md) — status codes mapped to failure modes.

## Companion docs

- **[CONCEPTS.md](CONCEPTS.md)** — rung map, concept index (where
  is *X* introduced?), the chapter dependency graph, and two
  alternative reading orders for readers who would rather start
  top-down or from the VM.
- **[GLOSSARY.md](GLOSSARY.md)** — quick definitions for every term
  used across the book (Forth, x86-64, C compiler, bootstrapping).

## The book is literate

Every fenced code block tagged `file=<path>` is the canonical source
for that file.  `tools/tangle.sh verify --strict` confirms the book
and the source agree byte-for-byte; that strict check is the
literate-program claim that "the book compiles."  Operator details
(`tangle.sh extract`, `status`, the per-file migration policy) live
in `CLAUDE.md` at the repo root.
