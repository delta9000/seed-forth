# Chapter 32 — End to End: Main and the Bootstrap Chain

> **Status:** structural stub.

## Goal

By the end of this chapter the reader can:

- read `120-cc-main.fth`'s 12-line `cc-main` and explain the order
  of operations end to end;
- run the full bootstrap chain (`tests/cc/stage-a-check.sh`) and
  understand each step;
- verify the byte-identical M1 output against the GCC-built
  M2-Planet reference and explain what the equality demonstrates.

## Source coverage

`120-cc-main.fth` (37 lines) and `tests/cc/stage-a-check.sh` plus
`tests/cc/bootstrap-chain.sh`.

## Concepts introduced

- **`cc-main`'s nine-step dance.**  load-stdin → preprocess →
  out-init → globals-init → emit-elf-header → parse-program →
  finalize-globals → finalize-elf → write-output → bye.
- **Stage A: parity with GCC.**  `stage-a-check.sh` uses our seed-
  built compiler to compile M2-Planet, then diffs the M1 output
  against a GCC-built reference.  Equality = scientific result.
- **The full bootstrap chain.**  `bootstrap-chain.sh` extends the
  story: stage0-posix → hex0-seed → seed-forth → cc-out → M2-Planet
  → MesCC → ... → a self-hosting GCC.
- **Reproducibility.**  The same inputs produce the same outputs;
  the test suite enforces this on every commit.

## Concepts carried in

- All of Parts I, II, III converge here.

## Concepts deferred

- Nothing — this is the end of the book proper.  Appendices follow.

## Section plan

1. **`cc-main` line by line.**  Walk all 12 lines.  Identify which
   chapter wrote each piece (`cc-load-stdin` from Ch 21,
   `cc-preprocess` from Ch 22, `cc-parse-program` from Chs 29–31,
   etc.).  This is the moment the reader sees the whole compiler
   composed.
2. **The `cc-out-path` constant.**  The 12-byte buffer holding
   `/tmp/cc-out\0`.  Read it byte by byte (it's a
   `create`-with-byte-data, Ch 12).
3. **`stage-a-check.sh`.**  Read the shell script.  Steps: build
   seed-forth; build cc-out via seed-forth + `cat *.fth`; compile
   M2-Planet's monolith with cc-out; diff against a GCC-built
   reference.
4. **What the diff equality proves.**  Our 2,040 hand-coded bytes,
   loaded through stage0-posix's `hex0-seed`, expanded through
   `010-lib.fth`, run through the 8,000-line C compiler in 020–110,
   compile a 10,000+-line real-world C program (M2-Planet) into
   byte-identical M1 output as if GCC had done it.  No magic step;
   every byte is auditable.
5. **`bootstrap-chain.sh`.**  The longer story: stage0-posix's
   229-byte `hex0-seed` is itself derived from a smaller seed; our
   chain plugs into the Guix Full Source Bootstrap.  Sketch the
   diagram from the Prologue and tick each step.
6. **Where to go from here.**  Pointers: extending the C subset
   (Appendix D exercises), adding new primitives to the seed
   (Appendix A), reading other bootstrap projects (oriansj, Guix,
   bootstrappable.org).

## Canonical source

```
\ TODO when writing: emit
\   ```forth file=120-cc-main.fth
\   <body of 120-cc-main.fth>
\   ```
\ Then walk through stage-a-check.sh and bootstrap-chain.sh as
\ illustrative shell snippets (no file= tag — they live outside
\ the literate tangle).
```

## Try it

```sh
./build.sh                   # 2,040-byte seed-forth
./test.sh                    # unit tests across all layers
tests/cc/stage-a-check.sh    # the byte-identical proof
tests/cc/bootstrap-chain.sh  # the full closure (slower)
```

If `stage-a-check.sh` reports
`self-v1-amd64.M1 == self-ref-amd64.M1`, you have reproduced the
project's central claim.

## Exercises

1. Run `tests/cc/bootstrap-chain.sh` and time each step.  Which is
   the slowest?  Could you speed it up without breaking
   byte-identity?

2. Add a primitive to `000-seed.hex0` (say, `mod` from Ch 15's
   exercises).  Rebuild and run `./test.sh` plus
   `stage-a-check.sh`.  What invariants might you have broken?

3. The `cc-out-path` is hard-coded to `/tmp/cc-out`.  Modify it to
   read a path from argv (the seed doesn't expose argv directly;
   you'll have to add a primitive).  What's the smallest change?

4. Sketch what it would take to extend the compiler to a different
   target architecture (RISC-V, ARM64).  Which files change?
   Which are reusable?

## Takeaways

- `cc-main` is 12 lines.  Everything else this book covered is
  scaffolding for those 12 lines.
- Stage-A parity with GCC is the proof of correctness: same
  bytes-in, same bytes-out, no hidden steps.
- The bootstrap chain is reproducible end-to-end; this book is
  the manual for the bottom 10 KB of it.

You have reached the end of the main book.  See the appendices
for reference cards, the memory map, the full reproducible
chain, and exercises with worked solutions.
