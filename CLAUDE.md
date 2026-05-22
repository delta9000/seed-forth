# CLAUDE.md

Project briefing for Claude Code sessions on `seed-forth`.

## What this repo is

A 2,040-byte hex0-encoded x86-64 Forth, plus a C-subset compiler
written in Forth on top of it, plus a 32-chapter literate book
that teaches both.  Stage-A check proves byte-identity of our
compiler's M1 output against GCC-built M2-Planet.

## Where things live

- `000-seed.hex0` — hand-coded Forth ELF seed (752 lines of hex).
- `010-lib.fth` — Forth library on top of the seed's 32 primitives.
- `020-…-fth` through `120-cc-main.fth` — the C compiler, loaded
  in numeric order.
- `book/` — literate-programming book.  Every fenced code block
  tagged `file=...` is the canonical source for that file.
- `vendor/stage0-posix`, `vendor/M2-Planet`, `vendor/mescc-tools`
  — pinned submodules.
- `tests/cc/stage-a-check.sh` — the byte-identity proof.
- `REPRODUCIBLE.md` — full fixed-point chain (deeper than book
  Appendix C, which is the reader-facing summary).
- `AI_STRATEGIES.md` — how this codebase got built (models,
  harnesses, what each was used for).

## The book is literate — invariant

`tools/tangle.sh verify --strict` must pass byte-identical on
every file before any session ends.  Run it after touching any
chapter that contains `file=...` fences.  If it fails on a
chapter you didn't touch, the previous chapter's closing fence is
missing a trailing blank line — chapter boundaries must preserve
the exact blank-line structure of the source file.

## When writing book chapters

`book/WRITING.md` is the protocol.  `book/CONCEPTS.md` is the
dependency graph: a chapter is safe to write only when its
prereqs are at least 📝.  Source order is the default load order
unless the dependency graph forbids it.

## Don't

- Don't bulk-rename across `Ch N` references without checking
  `book/CONCEPTS.md` — chapter numbers are load-bearing.
- Don't edit `000-seed.hex0` casually.  Layout addresses are
  baked into `010-lib.fth` literals.
- Don't bypass `tools/tangle.sh verify --strict` — it's the
  literate-program correctness check.
- Don't commit unless asked.  Leave staged-but-uncommitted for
  review.

## Quick health check

```sh
./check-all.sh                 # build + test + tangle --strict + stage-A
```

`check-all.sh` runs all four checks in sequence with per-step
pass/fail logging.  Use it before committing or after editing any
fenced code block in `book/`.  The individual commands are still
useful for diagnosing a failure:

```sh
./build.sh                     # produces 2040-byte seed-forth
./test.sh                      # smoke tests for layers 010-070
tools/tangle.sh verify --strict
tests/cc/stage-a-check.sh      # byte-identical M1 vs GCC
```
