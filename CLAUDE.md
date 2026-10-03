# CLAUDE.md

Project briefing for Claude Code sessions on `seed-forth`.

## What this repo is

A 1,772-byte hex0-encoded x86-64 Forth, plus a C-subset compiler
written in Forth on top of it, plus an M1 assembler / hex2 linker
in Forth (`130-asm.fth`), plus a 34-chapter literate book that
teaches all three.  Stage-A check proves byte-identity of our
compiler's M1 output against GCC-built M2-Planet.

## Where things live

- `000-seed.hex0` — hand-coded Forth ELF seed (689 lines of annotated hex).
- `010-lib.fth` — Forth library on top of the seed's 32 primitives.
- `020-…-fth` through `120-cc-main.fth` — the C compiler, loaded
  in numeric order.  The parser is `100-cc-expr.fth` (expressions),
  `110-cc-decl.fth` (declarations, Ch 29), `112-cc-stmt.fth`
  (statements, Ch 30), `114-cc-func.fth` (function definitions) and
  `116-cc-prog.fth` (file scope, entry stub, driver; both Ch 31).
  Scripts use `tools/compiler-layers.sh`: all numbered compiler libraries
  first, then the executing `120-cc-main.fth` last. A raw numeric glob
  would start reading C before optional layers numbered after 120 load.
- `130-asm.fth` — the M1 assembler / hex2 linker (book Ch 33).  Loads
  on `010-lib.fth` alone; `bootstrap.sh` uses it to build `M1` and
  `hex2` without GCC.
- `book/` — literate-programming book.  Every fenced code block
  tagged `file=...` is the canonical source for that file.
- `vendor/stage0-posix`, `vendor/M2-Planet`, `vendor/mescc-tools`,
  `vendor/pnut` — pinned submodules.
- `tests/pnut/sf-pnut-check.sh` (i386 route to TinyCC, pnut's kit
  unchanged) and `tests/pnut/sf-pnut-amd64-check.sh` (amd64 route:
  seed-forth → SF-built pnut → tcc-0.9.27 x86_64, every stage hash
  pinned; test programs in `tests/pnut/amd64/`).
- `patches/amd64/` — our patches for the amd64 route (pnut heap size,
  4 tcc-0.9.27, 6 portable_libc), unified diffs with explanatory
  headers, applied to scratch copies with exact manifests; never edit `vendor/pnut`.
  `tools/amd64-start.fth` builds the recipe runner directly from the seed;
  `tools/amd64.recipe` contains explicit operations and artifact pins. See
  `HOST-TOOLS.md` for the shell-free boundary and focused checks.  After
  changing one, re-pin with `SF_PNUT64_REPIN=1` (see its README).
- `gcc64/run-gcc64.sh` — the amd64 chain on from `tcc-boot2` to GCC 15.2
  via musl (standalone stage 0 = `tests/tcc/kernel-route-check.sh`,
  raw direct route; explicit `GCC64_STAGE0` verifies artifact pins in
  `tools/tcc.recipe`, not supplied provenance; ~1.5 h, so only in
  `verify.sh` with `VERIFY_GCC64=1`).  Sources pinned in `gcc64/SOURCES`
  (fetched into gitignored `build-out/gcc64-cache`, never committed),
  artifact pins in `gcc64/HASHES` (`root`-scoped ones embed the build
  path), patches in `patches/gcc64/` (provenance header on each), tests in
  `tests/gcc64/`.  See `gcc64/README.md`.
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
- Don't edit `000-seed.hex0` casually.  Every link, rel32, rel8,
  `LATEST`'s initial value and `[lit]`'s `lit_code` address are
  hand-computed from the layout, and the book's Part II quotes the
  offsets.  `010-lib.fth` types in no seed address; it relies only on
  the sysvar order STATE, LATEST, HERE (`here-addr`,
  `skip-vm-pages`).
- Don't bypass `tools/tangle.sh verify --strict` — it's the
  literate-program correctness check.
- Don't commit unless asked.  Leave staged-but-uncommitted for
  review.

## Quick health check

```sh
./check-all.sh                 # build, tests, tangle --strict, book numbers/index/links, try-it, stage-A, bootstrap, pnut (i386, amd64), handoff
```

`check-all.sh` runs all sixteen steps in sequence with per-step
pass/fail logging.  Use it before committing or after editing any
fenced code block — or any exact byte count, offset, or file line
count in prose — in `book/`.  The individual commands are still
useful for diagnosing a failure:

```sh
./build.sh                     # produces 1772-byte seed-forth
./test.sh                      # smoke tests for layers 010-070
tests/tcc/native-check.sh      # opt-in direct compiler regression gate
tests/tcc/kernel-route-check.sh # actual direct kernel/ladder host entry; QEMU is separate
tools/tangle.sh verify --strict
tools/check-numbers.py         # prose's exact numbers vs source (--dump shows the table)
tools/check-tryit.py           # runs every Try-it block against ./seed-forth
tests/cc/stage-a-check.sh      # byte-identical M1 vs GCC
./bootstrap.sh                 # GCC-free build: seed -> M2-Planet, M1, hex2 (fixed point)
./verify.sh                    # every comparison against GCC-built references
tests/cc/stage0-check.sh       # stage0-posix route vs Forth route (needs stage0 nested submodules)
tests/pnut/sf-pnut-check.sh    # our compiler builds unmodified pnut; SF_PNUT_TCC=1 goes on to tcc-0.9.27
tests/pnut/sf-pnut-amd64-check.sh  # amd64 route to tcc-0.9.27 (~10 s, no gcc); SF_PNUT64_GCC_ORACLE=1 adds the gcc reference
./handoff.sh                   # Forth route reproduces stage0-posix's AMD64 and x86 bin/ (19/19 answers each)
gcc64/run-gcc64.sh             # amd64 tcc-boot2 -> musl -> gcc-4.0.4/4.7.4/10.5.0 -> GCC 15.2 (~1.5 h; not in check-all)
tools/gen-index.py --check     # book/WORD-INDEX.md is up to date
tools/check-links.py           # every link and anchor in book/ resolves
```

`tools/check-numbers.py` is the numeric counterpart to the tangle
check: tangle proves `file=`/`chunk=` blocks byte-identical to source,
and check-numbers proves the book's *prose* byte counts, code offsets,
and file line counts against `000-seed.hex0` and the source files —
the layer that used to drift silently.
