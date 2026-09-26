# Where this fits in the bootstrap ecosystem

In his 1984 Turing Award lecture, "Reflections on Trusting Trust,"
Ken Thompson described a C compiler he had rigged to do two things:
plant a backdoor whenever it compiled the Unix `login` program, and
plant both tricks again whenever it compiled a clean copy of its own
source.  Build it once, delete the evil lines from the source, and
the binary keeps lying forever.  Reading source cannot catch it,
because the compiler you would check with was built by an earlier
compiler, and so on back.

The response that works is to make the first binary small enough to
read by hand and build everything else from source upward.  The
Bootstrappable Builds project (bootstrappable.org) maintains such a
chain, from stage0-posix's 229-byte `hex0-seed` up to a self-hosting
GCC.  GNU Guix consumes it; Live-Bootstrap
(`github.com/fosslinux/live-bootstrap`) runs it end-to-end.  This
book builds a second, independent path through **one rung** of that
ladder, M2-Planet.

## The Full Source Bootstrap, top to bottom

A loose sketch of the chain:

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
         The claim: these M1 texts are byte-identical.
         Checked on M2-Planet's own source (Stage A,
         2.3 MB of M1) and its 36 test programs
         (bootstrap-chain.sh)
```

The two ELFs are not byte-identical and never will be.  What is
byte-identical is what they each *emit* when fed the same C input.

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
affect what our Forth compiler emits, and vice versa.

## What this adds: cross-validation

The Bootstrappable chain already works.  What this project adds is
a **second, independent route** from `hex0-seed` to M2-Planet whose
output can be compared byte for byte against the first.  What is
actually checked:

- **Stage A** (`tests/cc/stage-a-check.sh`): the Forth-built
  M2-Planet compiles M2-Planet's own source to the same 2,367,260
  bytes of `.M1` as a GCC-built M2-Planet.
- **`STAGE0_COMPAT=1`**: with one optimization switched off, the
  Forth-built compiler's self-compile `.M1` matches a
  stage0-posix-built M2-Planet's instead (see `REPRODUCIBLE.md`).
- **Fixed point** (`tests/cc/bootstrap-chain.sh`): the compiler
  rebuilt from its own output reproduces that output exactly, and
  matches the reference on all 36 of M2-Planet's test programs.

That is the shape of David A. Wheeler's answer to Thompson,
*diverse double-compiling*: a planted trick would have to exist in
both independent routes, identically, to survive the comparison.

What it does not add: it does not shrink the trust root.  Both
routes still start at the 229-byte `hex0-seed`, on a Linux kernel
and a CPU nobody here audits.  It proves agreement on the inputs
above, not on every C program.  And it stops at M2-Planet;
everything from there to GCC still goes through GNU Mes and the
Live-Bootstrap chain.

## What this also demonstrates: auditable AI collaboration

There is a second reason this route was built, and built as a
literate book.  Most of the code here was written by AI (see the
prologue, and `AI_STRATEGIES.md`).  The byte-identity oracle that
makes cross-validation work does double duty: it is also a
correctness check a language model cannot bluff past.  Parity and
fixed-point closure are byte-level facts.  Plausible code that is
subtly wrong fails them, so they bound *correctness* without a
human reading every line.  The book bounds *understanding*: it is
the layer in which a person can follow, hold, and vouch for what
the machine produced.  The bootstrap is an unusually clean place to
show this, because its ground truth is absolute, but the shape
generalises: give the AI a mechanical oracle it can't argue with,
then write the literate explanation that keeps a human in command.

## Honest sizing

Does this route shrink the bootstrap?  No.  At the source-line level, the two routes are
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
specific bugs: where the two agree, neither route's
language-specific failure modes are in play.

The 2,040-byte seed is the part that *is* genuinely smaller than
stage0's equivalent intermediate stages.  On the AMD64 path, hex0
plus hex1 plus hex2 plus M0 add up to ~7 KB of executable before
you have a programmable layer.  We get to a programmable layer
(a working Forth) in 2 KB because Forth's primitives are short
and the dictionary structure is dense.  But the *total* source
budget above hex0-seed is comparable, because Forth is a means,
not a savings.

## Trust roots, plural

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

Next: [Prologue — Two Thousand and Forty Bytes](00-prologue.md).
