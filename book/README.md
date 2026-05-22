# Forth From a 2040-Byte Seed

2,040 bytes of hand-encoded x86-64 ELF, a Forth that those bytes
boot into, and about 7,400 lines of Forth code that build a C
compiler whose `.M1` output is byte-identical to GCC-built
M2-Planet.  This book is the manual for all of it.

The sidebar is the table of contents.  If you're new, start with
**Where this fits in the bootstrap ecosystem** (for context) and
then the **Prologue** (for the book's voice); the numbered
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

Smoke check from a fresh clone:

```sh
git submodule update --init --recursive
./check-all.sh                  # build + tests + tangle strict + Stage-A
```

If `check-all.sh` ends with all four lines reporting OK, the
codebase is reproducing the canonical artifacts.  See
**Troubleshooting** below if anything fails.

## How the book is organized

Three parts plus a prologue and seven appendices.  Chapter order
is **source order**: chapter *n* explains the code that appears at
offset *n* in the source files.  Every fenced code block tagged
`file=<path>` is the canonical source for that file; when
`tools/tangle.sh verify --strict` passes, the book *is* the
codebase.

- **Part I (Chs 1–12)** walks `010-lib.fth` — the Forth library
  above the seed.  Run examples in gforth.
- **Part II (Chs 13–20)** opens the 2,040-byte seed itself.  By
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
details (`tangle.sh extract`, `status`, the per-file migration
policy) live in `CLAUDE.md` at the repo root.
