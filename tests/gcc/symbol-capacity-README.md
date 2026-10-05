# Bounded live-symbol capacity for original GCC translation units

The sole production compiler change raises `cc-sym-cap` from 4096 to 8192.
The 1772-byte seed is unchanged. `cc-sym-add` still checks the prospective
count before writing; the first excess live row still fails with error 60.
Scope pops reclaim rows, and every reused row still clears its five auxiliary
columns, including qualification provenance.

## Measurement and independent limits

An isolated replay of the original-source-derived GCC 4.0.4 `c-parse.c`, with
its actual generated/configuration headers and Makefile compile flags,
reproduced error 60 at preprocessed line 26473 with the baseline compiler.
The 8192-row compiler progresses to error 10 at line 26818. Diagnostic-only
in-memory counters measure a live-symbol high-water of 4177 at that point;
the next arena allocation requests 8388760 used bytes, 152 bytes beyond the
separate 8388608-byte arena. These diagnostics do not change the production
sources, suppress checks, or rewrite GCC input. No `c-parse.o` is produced.
This proves removal of the measured symbol barrier, not completion of GCC.

Doubling the ten 8-byte symbol columns adds 327680 dictionary bytes. The
`cc-sysv-signatures` column also derives its bound from `cc-sym-cap`, adding
32768 bytes. Production compiler library loading moves `HERE` from 15224043
to 15584491; including the linker moves it from 15298690 to 15659138, leaving
5312382 bytes below the unchanged seed mapping end at 20971520 (`0x1400000`).
The seed maps 16 MiB beginning at `0x400000`; its size is not the end address.

The implicit-function record count also uses `cc-sym-cap`; its records and
signatures still consume the separately checked arena. Object metadata,
ELF symbols, relocations, and text/data buffers have independent capacities.
They are intentionally not resized by this change.

Baseline compiler identity:
`8b2978dab520d69d3aa260fcf9337272e1c7a9795da06fe810d6d34c90796113`.
Candidate identity:
`a2d556ad5ae55554794afdfa184e1b82d71abdd0bd405726e8c189487dc2a1bb`.

## Focused gate

Run from the repository root:

```sh
python3 tests/gcc/symbol-capacity-check.py
tests/cc/run-die-gate.sh die-60-symbols-full.sh 60 'cc: line 8162: error 60'
tools/tangle.sh verify --strict
```

The gate fills and reads all 8192 rows, checks the cap-derived signature
column's first and last cells, rejects row 8193, and recycles the last row
through a real scope push/pop while checking all five auxiliary cells reset.
It verifies actual dictionary endpoints with and without the capacity change.
Ten existing legacy/native fixtures produce byte-identical executables and
retain their expected exit/output behavior. A full C object fixture reaches
exactly 8192 live symbols; one excess row preserves an existing output and
publishes no fresh output. The existing legacy error-60 fixture remains in
the gate registry with the new exact error line.

All target preprocessing, compilation, ELF generation, and execution use the
seed and its Forth libraries. Python generates fixture text and checks bytes;
no host compiler, assembler, linker, or preprocessor is used in this gate.
The source-derived GCC replay consumes copied original source and generated
headers only, never the independent host generator cohort's outputs.
