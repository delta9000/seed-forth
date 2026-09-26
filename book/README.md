# Forth From a 1772-Byte Seed

A compiler binary can carry a backdoor that no reading of its
source will find; Ken Thompson showed how in 1984.  The defence is
a first program small enough to check by hand.  Here that program
is 1,772 bytes of hand-encoded x86-64: a Forth that, given its
library and 7,198 lines of compiler source (`020-cc-arena.fth`
through `120-cc-main.fth`, by `wc -l`), becomes a C compiler whose `.M1` output is byte-identical to
GCC-built M2-Planet's.  This book walks every one of those bytes and
lines, and backs each of its central claims with a command you can run.

The sidebar is the table of contents.  If you're new, start with
**Where this fits in the bootstrap ecosystem** (for context) and
then the **Prologue** (which opens with the whole pipeline running); the numbered
chapters take over from Chapter 1.

## Audience

You write code already.  You know what a stack is, what `malloc`
does, and roughly what an ELF executable is.  You have never
written Forth (or you tried once, found the `: ;` syntax baffling,
and bounced off).

You do **not** need to know x86-64 assembly, the ELF format in
detail, the Linux syscall ABI, the Forth standard library, or
anything about bootstrap chains.  The book introduces each of
these as it needs them, in the order it needs them.

## By the end of this book you will be able to

- Pick any line in `010-lib.fth`, the 32 primitives in
  `000-seed.hex0`, or the C compiler files and explain what it
  does, why it's shaped that way, and what would break if it
  weren't.
- Run `./check-all.sh` and explain what each of its eight steps
  proves about the artifact.
- Audit the Stage-A parity claim yourself: rebuild the chain from
  the 229-byte hex0 trust root through the 1,772-byte seed, the
  Forth library, and the C compiler, and verify that the emitted
  `.M1` text matches a GCC-built reference byte-for-byte.
- Read related codebases (M2-Planet, mescc-tools, stage0,
  JONESFORTH, sectorforth) with confidence.  The skill of reading
  dense low-level code carries over.
- Know what you cannot do: the book is a manual for one specific
  chain, not a survey or a how-to-design-your-own.  Pointers to
  go further live in **Appendix E — Further Reading**.

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
  version).  Most of Part I runs there; Chs 5, 10, and 11 need a
  built seed, because their words lean on seed machinery (`syscall6`,
  the real dictionary, inline branch slots) that gforth doesn't
  reproduce.
- **git** to clone the repo with its `vendor/` submodules
  (stage0-posix's `hex0-seed` is checked in there).
- **A C compiler** (gcc) and **make** **only** if you want to run
  the Stage-A check (Appendix C) and the small assembler checks;
  the book itself never invokes them.

Disk budget: ~30 MiB for the repo plus vendored stage0-posix /
M2-Planet / mescc-tools.  Memory: a few MiB at runtime; the C
compiler reserves a 256 MiB heap but only touches what it uses.

Smoke check from a fresh clone:

```sh
git submodule update --init --recursive
./check-all.sh                  # build, tests, asm, C gates, tangle, numbers, Stage-A
```

`check-all.sh` runs eight steps and prints one OK/SKIP/FAIL line
for each: `01-build` (the 1,772-byte seed), `02-test` (the layer
smoke tests), `02a-asm` (three small assembler checks),
`02b-gates` (the registered C-compiler gates), `03-tangle-strict`
(book and source byte-identical), `04-book-numbers` (the prose's
exact numbers against source), `04a-tryit` (every runnable
Try-it block, run against the built seed), and `05-stage-a` (the byte-identical
`.M1`).  `02a-asm` and `05-stage-a` need gcc and make and report
SKIP without them; `04-book-numbers` and `04a-tryit` need python3.  If it ends
with `check-all: all 8 steps PASS`, the codebase is reproducing the
canonical artifacts.  See
**Troubleshooting** below if anything fails.

## How the book is organized

Three parts plus a prologue and seven appendices.  Within each
part, chapters follow **source order**: each one picks up the file
where the previous chapter stopped.

- **Part I (Chs 1–12)** walks `010-lib.fth`, the Forth library
  above the seed.  Run most examples in gforth; Chs 5, 10, and 11
  need a built seed.
- **Part II (Chs 13–20)** opens the 1,772-byte seed itself.  By
  the end, no primitive is a black box.
- **Part III (Chs 21–32)** walks the C compiler in twelve
  chapters, ending at the Stage-A byte-identity proof.
- **Appendices A–G** are reference cards: primitives, memory
  map, reproducibility chain, worked exercises, further reading,
  C subset, and compiler exit codes.

Two companion docs help readers navigate:

- **[CONCEPTS.md](CONCEPTS.md)** — concept index ("where is *X*
  introduced?"), dependency graph, and alternative reading orders
  for top-down readers.
- **[GLOSSARY.md](GLOSSARY.md)** — quick definitions for every
  term used across the book.  Bookmark this if you hit unfamiliar
  vocabulary; the chapters don't redefine terms.

## Troubleshooting

The most common failures on a fresh checkout, in roughly the
order you'd hit them:

| Symptom | Likely cause | Fix |
|---|---|---|
| `build.sh` says `hex0-seed: No such file or directory` | submodules not initialised | `git submodule update --init --recursive` |
| `build.sh` runs but produces 0 bytes | `hex0-seed` not executable on this filesystem (some Windows / network mounts) | `chmod +x vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed` |
| `cannot execute binary file: Exec format error` | wrong host architecture (Apple Silicon, ARM) | Run the build inside an `amd64` VM, container, or QEMU-user. |
| `stage-a-check.sh` says `make: command not found` or `cc: ...` | GCC / make not installed | Install `build-essential` (Debian/Ubuntu) or equivalent. Only Stage-A needs it; `test.sh` does not. |
| Stage-A check fails on the `.M1` diff | something in `vendor/M2-Planet` drifted from the pin | `cd vendor/M2-Planet && git checkout 0a67a68` (see `REPRODUCIBLE.md` for canonical pins) |
| `tangle verify --strict` reports a file mismatch | edit drifted between book block and source file | The source file is authoritative if you edited it directly; re-run `tools/tangle.sh extract /tmp/out` and diff. |
| Out of disk during the Stage-A monolith build | `/tmp` is on a small tmpfs | `BUILDROOT=/var/tmp/seed-bootstrap ./tests/cc/stage-a-check.sh` |

## The book is literate

Every fenced code block tagged `file=<path>` is the canonical
source for that file.  `tools/tangle.sh verify --strict` confirms
the book and the source agree byte-for-byte; that strict check is
the literate-program claim that "the book compiles."  Operator
details (`tangle.sh extract`, `status`) live in `tools/tangle.sh`
and `CLAUDE.md` at the repo root.
