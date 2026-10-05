# Forth From a 1772-Byte Seed

A compiler binary can carry a backdoor that no reading of its
source will find; Ken Thompson showed how in 1984.  The defence is
a first program small enough to check by hand.  Here that program
is 1,772 bytes of hand-encoded x86-64: a Forth that, given its
library and 12,089 lines of compiler source (`020-cc-arena.fth`
through `120-cc-main.fth`, by `wc -l`), becomes a C compiler whose `.M1` output is byte-identical to
GCC-built M2-Planet's, and whose opt-in LP64 extension compiles
TinyCC directly. This book walks every one of those bytes and lines, and backs each of its central claims with a command you can run.

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
  `000-seed.hex0`, the C compiler files, or the assembler
  `130-asm.fth` and explain what it
  does, why it's shaped that way, and what would break if it
  weren't.
- Run `./check-all.sh` and explain what each of its sixteen steps
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
- **A C compiler** (gcc) **only** if you want to run the Stage-A
  check (Appendix C) and the other comparisons against GCC-built
  references (`./verify.sh`); the book itself never invokes it, and
  `./bootstrap.sh` builds the whole chain without it.

Disk budget: ~30 MiB for the repo plus vendored stage0-posix /
M2-Planet / mescc-tools. Memory: the seed maps 16 MiB; legacy
generated programs reserve a 256 MiB heap but only touch what they use. The direct TinyCC compiler adds an 8 MiB scratch mapping; the experimental
direct-GCC driver requests a fixed 16 MiB scratch mapping instead. The
generated TinyCC seed uses portable libc's static heap. Appendix B
separates these allocations.

Smoke check from a fresh clone:

```sh
git submodule update --init --recursive
./check-all.sh                  # build, tests, asm, C gates, tangle, numbers, Stage-A, bootstrap
```

`check-all.sh` runs sixteen steps and prints one OK/SKIP/FAIL line
for each: `01-build` (the 1,772-byte seed), `02-test` (the layer
smoke tests), `02a-asm` (four small assembler checks),
`02b-gates` (the registered C-compiler gates), `02c-native`
(the opt-in LP64/bootstrap compiler regressions), `03-tangle-strict`
(book and source byte-identical), `04-book-numbers` (the prose's
exact numbers against source), `04a-tryit` (every runnable
Try-it block, run against the built seed), `04b-index` (the committed
[Index](WORD-INDEX.md) matches what `tools/gen-index.py` generates),
`04c-links` (book links and anchors resolve),
`05-stage-a` (the byte-identical
`.M1`), `06-bootstrap` (`./bootstrap.sh`, the GCC-free build up to
M2-Planet's self-hosting fixed point; Appendix C), `06a-pnut`
(the i386 pnut control), `06b-pnut-amd64` (the amd64 pnut/TinyCC
control), `06c-direct-tcc` (the actual direct kernel/ladder host entry),
and `07-handoff`
(stage0-posix's own recipe fed by the Forth route; SKIP without its
nested submodules).  `02a-asm` and
`05-stage-a` need gcc, only to build the references they compare
against, and report SKIP without it; `04-book-numbers`, `04a-tryit`,
`04b-index`, `04c-links`, `02c-native`, and `06c-direct-tcc` need
python3. Guest boot/handoff checks under QEMU are separate from this
host entry check.  If it ends
with `check-all: all 16 steps PASS`, the codebase is reproducing the
canonical artifacts.  See
**Troubleshooting** below if anything fails.

## How the book is organized

Five established parts, an experimental direct-GCC part, a prologue, and seven appendices.  Within each
part, chapters follow **source order**: each one picks up the file
where the previous chapter stopped.

- **Part I (Chs 1–12)** walks `010-lib.fth`, the Forth library
  above the seed.  Run most examples in gforth; Chs 5, 10, and 11
  need a built seed.
- **Part II (Chs 13–20)** opens the 1,772-byte seed itself.  By
  the end, no primitive is a black box.
- **Part III (Chs 21–32)** walks the C compiler in twelve
  chapters, ending at the Stage-A byte-identity proof.
- **Part IV (Ch 33)** walks `130-asm.fth`, the Forth M1 assembler
  and hex2 linker that `./bootstrap.sh` uses to build mescc-tools'
  `M1` and `hex2` without GCC.
- **Part V (Ch 34)** extends the compiler to compile the pinned TinyCC
  and portable-libc sources directly. It separates the restricted seed
  profile from the rebuilt full compiler, and records the fixed-point
  and runtime checks. See [the direct route](https://github.com/delta9000/seed-forth/blob/master/tests/tcc/README.md) for
  its focused and independent fixed-point checks. The native regression
  gate and actual host entry are included in `check-all.sh`; QEMU guest
  checks remain separate.
- **Part VI (Chs 35–47, work in progress)** explains the reconstructed object,
  ABI, linker, archives, typed constants, header policy, variadic lists, and bounded
  runtime components, binary32/binary64 values, exact literals, and bitfields. It includes unchanged GCC source-unit proofs;
  a complete direct GCC bootstrap remains unfinished.
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
| `stage-a-check.sh` says `gcc not on PATH` | GCC not installed | Install `gcc` (Debian/Ubuntu: `build-essential`). Only the comparisons against GCC references need it; `test.sh` and `bootstrap.sh` do not. |
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
