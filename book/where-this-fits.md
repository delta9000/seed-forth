# Where this fits in the bootstrap ecosystem

This book is **one rung** of a longer ladder.  This page sketches
the ladder, names the rungs above and below, and pins down what
this project adds that the existing chain doesn't.

## The Full Source Bootstrap, top to bottom

The Bootstrappable Builds project (bootstrappable.org) maintains a
chain from a tiny hex-coded seed up to a self-hosting GCC, every
byte of which is auditable source.  GNU Guix consumes the chain;
the Live-Bootstrap project (`github.com/fosslinux/live-bootstrap`)
runs it end-to-end as a reproducible script.

A loose sketch of the chain, top to bottom:

```
        ┌─────────────────────────────────────────────┐
        │   GCC + glibc + GNU/Linux userland          │
        │   (the "real" toolchain, downstream of      │
        │    everything below)                        │
        └─────────────────────────────────────────────┘
                            ▲
                            │
        ┌─────────────────────────────────────────────┐
        │   TinyCC                                    │
        │   (a 100 KLOC C compiler)                   │
        └─────────────────────────────────────────────┘
                            ▲
                            │
        ┌─────────────────────────────────────────────┐
        │   GNU Mes (Janneke Nieuwenhuizen)           │
        │   Scheme/C interpreter; provides a C        │
        │   compiler (MesCC) that compiles TinyCC.    │
        └─────────────────────────────────────────────┘
                            ▲
                            │
        ┌─────────────────────────────────────────────┐
        │   M2-Planet (Jeremiah Orians)               │
        │   A self-hosting C-subset compiler.         │
        │   Output: M1 assembly, fed to mescc-tools.  │
        │   ◄────── THIS BOOK'S DELIVERABLE ────►     │
        │   ◄ proves byte-identity with this rung ►   │
        └─────────────────────────────────────────────┘
                            ▲
                            │
        ┌─────────────────────────────────────────────┐
        │   mescc-tools (M1 + hex2 + blood-elf)       │
        │   Assemble M2-Planet's text output to ELF.  │
        └─────────────────────────────────────────────┘
                            ▲
                            │
        ┌─────────────────────────────────────────────┐
        │   stage0-posix (Jeremiah Orians + others)   │
        │   Builds mescc-tools and M2-Planet from a   │
        │   229-byte hex0-seed via M0, M1, and        │
        │   hex0-equivalent assemblers, all in        │
        │   commented hex.                            │
        │   ◄────── THIS BOOK'S TRUST ROOT ──────►    │
        └─────────────────────────────────────────────┘
                            ▲
                            │
        ┌─────────────────────────────────────────────┐
        │   229-byte hex0-seed                        │
        │   (the smallest auditable artifact)         │
        └─────────────────────────────────────────────┘
                            ▲
                            │
        ┌─────────────────────────────────────────────┐
        │   Hardware: x86-64 CPU + Linux kernel       │
        │   (builder-hex0 reaches below this on bare  │
        │   metal; out of scope here)                 │
        └─────────────────────────────────────────────┘
```

This book lives in the **middle**: it builds a self-contained
2,040-byte Forth from `hex0-seed`, then uses that Forth to compile
a C-subset compiler whose `.M1` output is **byte-identical to
GCC-built M2-Planet on the M2-Planet self-compile**.  That equality
is the verification claim everything else rests on.

## What this project is, in one sentence

A second, independent path from `hex0-seed` to "a binary that
compiles M2-Planet to the same `.M1` bytes the canonical chain
does" — built in Forth, fully literate, and small enough to read
in a weekend.

## What it adds that didn't exist before

The Bootstrappable chain works.  Why a second path?

- **Independent cross-validation at the M2-Planet rung.**  The
  canonical chain reaches M2-Planet through stage0-posix's
  `cc_amd64`.  This project reaches M2-Planet through a Forth.
  Two implementations agreeing byte-for-byte on the same C source
  is a stronger correctness claim than either alone — exactly the
  kind of redundancy the Bootstrappable project actively wants.

- **A Forth lens on the bootstrap.**  Every existing rung is in
  C, Scheme, M0/M1, or hex.  Forth is small enough (32 primitives
  in 2,040 bytes) that it can be hand-encoded in hex0 *and*
  expressive enough to host a C compiler in 12 files.  That
  combination is unusual and instructive.

- **Literate pedagogy.**  The book *is* the source.  Every
  fenced code block tagged `file=…` tangles to the actual
  on-disk file with `tools/tangle.sh verify --strict` checking
  byte-identity.  Read the book; you have read the codebase.

- **A teaching artifact for the chain itself.**  Most of the
  Bootstrappable chain is engineering documentation — necessary
  but not pedagogical.  This book aims to teach Forth, x86-64
  ELF, and the shape of a small C compiler in the *order they
  appear in a real chain*, so the reader arrives at the M2-Planet
  byte-identity proof having earned every step.

## What it deliberately does *not* try to do

- **Replace the existing chain.**  This project is *an
  alternative entry point at the M2-Planet rung*, not a fork of
  the bootstrap.  It does not reach above M2-Planet (no MesCC,
  no TinyCC, no GCC).  Everything above this rung still goes
  through Janneke's GNU Mes and the Live-Bootstrap chain.

- **Cover non-x86-64 architectures.**  The seed is hand-encoded
  x86-64 ELF.  Porting would require a new `000-seed.hex0` and a
  rewrite of `090-cc-emit.fth`'s instruction encoders.  Out of
  scope for this book.

- **Be a production toolchain.**  The C subset is M2-Planet's
  subset — no floats, no varargs, no `union`, no
  `#ifndef`/`#endif`.  This is intentional: it is the *minimum*
  C that can compile M2-Planet, not the maximum C anyone might
  want.

## Cross-references

- The trust-root link (hex0-seed): **[Appendix C](A3-reproducibility-chain.md)**
  for the reader-facing walk-through; `REPRODUCIBLE.md` at the
  repo root has the operator-facing pins, SHA-256s, and the
  `STAGE0_COMPAT=1` notes.
- The C compiler's specification target (M2-Planet): see
  `vendor/M2-Planet/README.md`, or the original at
  `github.com/oriansj/M2-Planet`.
- The downstream consumer (Guix Full Source Bootstrap): see
  `bootstrappable.org` and `github.com/fosslinux/live-bootstrap`.
- Further reading: **[Appendix E](A5-further-reading.md)** has
  grouped pointers to Bootstrappable, stage0, M2-Planet, Mes, and
  the academic background.

## The byte-identity claim, made precise

`tests/cc/stage-a-check.sh` does this:

1. Build `seed-forth` from `000-seed.hex0` using stage0-posix's
   229-byte `hex0-seed` (no GCC in this step).
2. Build a reference `M2-Planet` from the same source using GCC.
3. Feed M2-Planet's monolithic source to `seed-forth` loaded
   with `010-lib.fth` through `120-cc-main.fth`.  Output:
   `/tmp/cc-out`, a 200 KB ELF that is itself a C compiler.
4. Run both `/tmp/cc-out` and the GCC-built reference on the
   *same* M2-Planet source set.  Diff the resulting `.M1` files
   byte-for-byte.
5. Equality is the proof.  Stage A passes when the diff is empty.

If anything in the chain — seed-forth, the Forth compiler, the
emitted code — were wrong, the M1 outputs would diverge and the
script would fail.
