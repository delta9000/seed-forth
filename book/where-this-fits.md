# Where this fits in the bootstrap ecosystem

The Bootstrappable Builds project (bootstrappable.org) maintains a
chain from a tiny hex-coded seed up to a self-hosting GCC, every
byte of which is auditable source.  GNU Guix consumes the chain;
the Live-Bootstrap project (`github.com/fosslinux/live-bootstrap`)
runs it end-to-end as a reproducible script.  This book is **one
rung** of that ladder, sitting at M2-Planet.

## The Full Source Bootstrap, top to bottom

A loose sketch of the chain, top to bottom:

```
        ┌─────────────────────────────────────────────┐
        │   GCC + glibc + GNU/Linux userland          │
        │   (the "real" toolchain, downstream of      │
        │    everything below)                        │
        └─────────────────────────────────────────────┘
                            ▲
        ┌─────────────────────────────────────────────┐
        │   TinyCC                                    │
        │   (a 100 KLOC C compiler)                   │
        └─────────────────────────────────────────────┘
                            ▲
        ┌─────────────────────────────────────────────┐
        │   GNU Mes (Janneke Nieuwenhuizen)           │
        │   Scheme/C interpreter; provides a C        │
        │   compiler (MesCC) that compiles TinyCC.    │
        └─────────────────────────────────────────────┘
                            ▲
        ┌─────────────────────────────────────────────┐
        │   M2-Planet (Jeremiah Orians)               │
        │   A self-hosting C-subset compiler.         │
        │   Output: M1 assembly, fed to mescc-tools.  │
        │   ◄────── THIS BOOK CONVERGES HERE ────►    │
        └─────────────────────────────────────────────┘
                            ▲
        ┌─────────────────────────────────────────────┐
        │   mescc-tools (M1 + hex2 + blood-elf)       │
        │   Assemble M2-Planet's text output to ELF.  │
        └─────────────────────────────────────────────┘
                            ▲
        ┌─────────────────────────────────────────────┐
        │   stage0-posix (Jeremiah Orians + others)   │
        │   Builds mescc-tools and M2-Planet from a   │
        │   229-byte hex0-seed via M0, M1, and        │
        │   hex0-equivalent assemblers, all in        │
        │   commented hex.                            │
        │   ◄────── THIS BOOK'S TRUST ROOT ──────►    │
        └─────────────────────────────────────────────┘
                            ▲
        ┌─────────────────────────────────────────────┐
        │   229-byte hex0-seed                        │
        │   (the smallest auditable artifact)         │
        └─────────────────────────────────────────────┘
                            ▲
        ┌─────────────────────────────────────────────┐
        │   Hardware: x86-64 CPU + Linux kernel       │
        │   (builder-hex0 reaches below this on bare  │
        │   metal; out of scope here)                 │
        └─────────────────────────────────────────────┘
```

This book starts at `hex0-seed` and ends at "a working M2-Planet
binary".  The interesting part is what "working" means, and that
turns out to be the whole story.

## Two routes, one M2-Planet

The canonical bootstrap reaches M2-Planet through stage0-posix's
`M0`, `M1`, `hex2`, and the rest of the `cc_amd64` toolchain (call
it the **stage0 route**).  This book reaches M2-Planet through a
2,040-byte Forth seed and a C-subset compiler written in Forth
(call it the **Forth route**).

Both routes start at the same place (`hex0-seed`, 229 bytes) and
end at the same place (a binary that *is* M2-Planet).  But the
ELFs they emit are different bytes, because each compiler makes
its own codegen choices.

```
              hex0-seed  (229 bytes, the shared trust root)
                 │
        ┌────────┴────────┐
        │                 │
        │ stage0 route    │ Forth route (this book)
        │  M0 → M1 →      │  000-seed.hex0 → seed-forth
        │  hex2 →         │  010-lib.fth → 020..120-cc-*.fth
        │  cc_amd64       │
        │                 │
        ▼                 ▼
   m2-ref            /tmp/cc-out
   (ELF binary)      (ELF binary)
        │                 │
        │                 │   different bytes!
        │                 │   both valid M2-Planet implementations
        │                 │
        │  run on any C source S
        │                 │
        ▼                 ▼
   M1 text             M1 text
   (M2-Planet's        (M2-Planet's
    own output         own output
    format)            format)
        │                 │
        └────────┬────────┘
                 ▼
         Stage A claim:
         these M1 texts must be byte-identical for every
         C source M2-Planet itself accepts, including
         M2-Planet's own source as input
```

The two ELFs are not byte-identical and never will be.  What is
byte-identical is what they each *emit* when fed the same C input.
Two different M2-Planet implementations that agree on M1 output
for every C input are, observationally, the same compiler.

Once you have either of these M2-Planet binaries, you feed its M1
output into mescc-tools and you're back on the canonical chain
heading up to Mes, TinyCC, and GCC.  The Forth route is a *swap-in
replacement* at the M2-Planet rung, not a fork of the bootstrap.

## What "working" actually means here

A paranoid auditor can pick which route to trust as their entry
into the Bootstrappable chain:

- **Trust the stage0 route.**  Read stage0-posix's hex.  Run its
  M0/M1/hex2 pipeline.  Get M2-Planet.
- **Trust the Forth route.**  Read this book.  Run
  `000-seed.hex0` through any hex0 assembler.  Get seed-forth.
  Load the twelve `.fth` files.  Get an M2-Planet-equivalent.

Both routes share the same `hex0-seed` (and the same Linux kernel,
and the same CPU), so the trust roots overlap.  Above the trust
roots they are independent: a bug in stage0's `cc_amd64` cannot
affect what our Forth compiler emits, and vice versa.  Stage A's
byte-identity check on M1 output is the proof that the two
independent paths landed at the same compiler behaviour.

That is the value of this project.  Not "a smaller bootstrap"
(stage0 is plenty small).  A **second route** that happens to also
be small, hand-readable, and built on Forth instead of M0/M1.

## What this adds: cross-validation

The Bootstrappable chain already works.  The reason for a second
path is **redundancy**: two implementations agreeing on M1 output
for every C input is a stronger correctness claim than either
alone, and is exactly the kind of cross-check the Bootstrappable
project actively wants at each rung.  Forth is the language that
makes this particular second path small enough to hand-read in
an afternoon (32 primitives in 2,040 bytes; a C compiler in
twelve files); it is the means, not the point.

This is not a fork of the bootstrap.  It does not reach above
M2-Planet.  Everything from there up to GCC still goes through
Janneke's GNU Mes and the Live-Bootstrap chain.

## Honest sizing

A natural question after reading the above: does this route shrink
the bootstrap?  No.  At the source-line level, the two routes are
comparable.

Approximate hand-written source above the shared `hex0-seed`,
counted as raw line counts in the AMD64 path of each route:

| Route                      | Hand-written source                  | Lines  |
|----------------------------|--------------------------------------|-------:|
| stage0 AMD64 (canonical)   | hex0 / hex1 / hex2 / M0 / M1 sources | ~10,000 |
| Forth (this book)          | `000-seed.hex0` + 12 `.fth` files    |  ~8,200 |

Both numbers are dominated by the small C compiler at the top of
their respective stages: stage0's `cc_amd64.M1` (in M1 macro
assembly) and our `100-cc-expr.fth` + `110-cc-decl.fth` (in
Forth).  Both are tens of percent bigger or smaller depending on
how you count comments, whitespace, and macro-expansion.  Treat
them as the same order of magnitude.

So the audit burden (lines a human has to read) is comparable.
What changes is *the language those lines are in*, and that
matters because:

- An auditor of stage0's route is reading hex columns, M0 macro
  expansions, and M1 assembly.  Mistakes hide as transcription
  errors, off-by-one address arithmetic, and macro-expansion
  surprises.
- An auditor of this book's route is reading hex bytes (for the
  seed only, 2,040 of them) and Forth.  Mistakes hide as
  stack-effect mistakes, wrong primitive choices, and codegen
  template errors.

Different bug surfaces.  An independent path catches bug *classes*
that the canonical path would have made invisible, not just
specific bugs.  This is the cross-validation argument made
concrete: two implementations that agree on M1 output for every
C input have ruled out *both* sets of language-specific failure
modes.

The 2,040-byte seed is the part that *is* genuinely smaller than
stage0's equivalent intermediate stages — hex0 plus hex1 plus hex2
plus M0 on the AMD64 path add up to ~7 KB of executable before
you have a programmable layer.  We get to a programmable layer
(a working Forth) in 2 KB because Forth's primitives are short
and the dictionary structure is dense.  But the *total* source
budget above hex0-seed is comparable, because Forth is a means,
not a savings.

## Trust roots, plural

"Auditable from a small trust root" is the honest pitch.  "Something
from nothing" is not what the Bootstrappable chain claims and not
what this book delivers either.

The trust root for either route through this book is the union of:

- the 229-byte `hex0-seed` (auditable in an afternoon),
- the Linux kernel (~30 million lines of C, not audited here),
- the x86-64 CPU and its microcode (opaque silicon).

stage0's bare-metal paths (`NATIVE/x86`, `NATIVE/knight`,
`builder-hex0`) push the trust root below the Linux kernel by
running on raw hardware with no OS.  Those paths exist; they are
not what this book sits on.  This book assumes a working Linux
kernel underneath, because that is what `000-seed.hex0`'s
`syscall` instructions talk to.  A future port could swap our
`syscall6` primitive for builder-hex0's bare-metal interface and
reach below.

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
   `/tmp/cc-out`, a 200 KB ELF that is itself a C compiler
   behaving as M2-Planet.
4. Run both `/tmp/cc-out` and the GCC-built reference on the
   *same* M2-Planet source set.  Diff the resulting `.M1` files
   byte-for-byte.
5. Equality is the proof.  Stage A passes when the diff is
   empty.

Note that we are *not* diffing `/tmp/cc-out` against the GCC-built
`m2-ref` ELF.  Those are different binaries, both valid.  We are
diffing what those two binaries *emit* on identical input.

If anything in either chain were wrong (seed-forth, the Forth
compiler, the GCC reference build, the M2-Planet source itself),
the M1 outputs would diverge and the script would fail.
