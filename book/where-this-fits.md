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

## If you are here to bootstrap

The practical facts first.

- **Host.**  amd64 Linux only.  The seed is an x86-64 ELF that makes
  Linux syscalls directly.  The compiler it builds can *emit* code
  for `x86` (32-bit) as well as `amd64`: `tests/cc/bootstrap-chain.sh`
  runs its stages once per entry in `ARCHES` (default `x86 amd64`),
  and running the 32-bit binaries it produces needs a kernel with
  32-bit support.
- **Time.**  `./check-all.sh` (build, unit tests, gates, the three
  book checks, Stage A) took about 30 s here; a cold
  `BUILDROOT=$(mktemp -d) tests/cc/bootstrap-chain.sh` took about
  40 s.  Both on a 4-core machine; yours will differ.
- **What you trust.**  The 229-byte `hex0-seed` from stage0-posix's
  `bootstrap-seeds` (`build.sh` runs it on `000-seed.hex0`; nothing
  else from stage0-posix is executed), the Linux kernel, the CPU, and
  the host `bash` and `cat` that pipe the sources into the seed.  The
  M2-Planet build (`tests/cc/build-m2planet-monolith.sh`) also runs
  the host `sed` to drop M2-Planet's `#include "..."` lines and
  duplicate `TRUE`/`FALSE` defines while it concatenates the C files.
- **Where GCC appears.**  Only as a reference.  Stage A and
  `bootstrap-chain.sh` build a GCC M2-Planet to compare against, and
  `bootstrap-chain.sh` currently assembles with GCC-built mescc-tools
  `M1` and `hex2`.  The GCC-free assembler is `130-asm.fth`: 689
  lines of Forth, an M1 expander and hex2 linker that no chapter
  teaches.  `tests/asm/m2planet-check.sh` shows that it assembles
  Stage A's M2-Planet `.M1` to the same bytes as mescc-tools.
- **Where it stops.**  At an M2-Planet-compatible compiler (plus
  `130-asm.fth`).  The hand-off that builds the rest of mescc-tools
  from it and continues into Mes, TinyCC and GCC is not written yet.

### Auditing the seed in an afternoon

The 1,772 bytes are the only part you cannot rebuild from source, so
start there.  Read Appendix B (the memory map) for the layout the
seed assumes.  Then read Part II in order, Chapters 13 to 20, with
`000-seed.hex0` open beside it: 13 is the ELF header, entry point
and sysvars; 14 to 16 are the stack, arithmetic and I/O primitives;
17 and 18 are the dictionary and the colon compiler; 19 and 20 are
branches, literals, the number parser and the REPL.  Keep
Appendix A (the 32 primitives and their byte budget) as the
checklist: every row should be a unit you have read.  Finish with
`./build.sh` (it must report 1,772 bytes) and
`tools/check-numbers.py`, which checks the offsets and byte counts
the chapters quote against the file.

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
        │   229-byte hex0-seed via hex1, hex2, M0     │
        │   and cc_amd64, all in commented hex or     │
        │   M1 assembly.                              │
        │   (The Forth route is an alternative path   │
        │    for this stretch.)                       │
        └─────────────────────────────────────────────┘
                            ▲
        ┌─────────────────────────────────────────────┐
        │   229-byte hex0-seed                        │
        │   (the smallest auditable artifact)         │
        │   ◄── THE ONLY STAGE0 PIECE THIS BOOK RUNS  │
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
`hex1`, `hex2`, `M0` and `cc_amd64`, a C-subset compiler written in
M1 assembly (call it the **stage0 route**).  This book reaches an
M2-Planet-compatible compiler through a 1,772-byte Forth seed and a
C-subset compiler written in Forth (call it the **Forth route**).

Both routes start at the same place (`hex0-seed`, 229 bytes) and
end with a binary that behaves as M2-Planet.  But those ELFs are
different bytes, because each compiler that built them makes its
own codegen choices.

```
              hex0-seed  (229 bytes, the shared trust root)
                 │
        ┌────────┴────────┐
        │                 │
        │ stage0 route    │ Forth route (this book)
        │  hex0 → hex1 →  │  000-seed.hex0 → seed-forth
        │  hex2 → M0 →    │  010-lib.fth → 020..120-cc-*.fth
        │  cc_amd64       │
        │                 │
        ▼                 ▼
   M2-Planet         /tmp/cc-out
   (ELF binary)      (ELF binary)
        │                 │
        │                 │   different bytes!
        │                 │   both valid M2-Planet implementations
        │                 │
        │  run on the same C source
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
```

The two ELFs are not byte-identical and never will be.  What is
byte-identical is what they each *emit* when fed the same C input.
The routine checks compare against a GCC-built M2-Planet, which is
quicker to build than running stage0; the comparison with a
stage0-built one needs `STAGE0_COMPAT=1` (see the list below).

In principle, once you have either binary you feed its M1 output
to mescc-tools and you are back on the canonical chain heading up
to Mes, TinyCC and GCC.  In practice that hand-off is not built
yet: nothing here produces `blood-elf`, `kaem` and the rest of
mescc-tools from the Forth route's compiler and passes them on.
Today the Forth route is an independent cross-check on stage0's
stretch from `hex1` to M2-Planet, and a candidate replacement for
it, not a drop-in one.

## What "working" actually means here

A paranoid auditor can pick which route to trust as their entry
into the Bootstrappable chain:

- **Trust the stage0 route.**  Read stage0-posix's hex and M1.  Run
  its hex1/hex2/M0/`cc_amd64` pipeline.  Get M2-Planet.
- **Trust the Forth route.**  Read this book.  Run
  `000-seed.hex0` through any hex0 assembler.  Get seed-forth.
  Load the fifteen `.fth` files.  Get an M2-Planet-equivalent.

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
  matches the GCC-built reference (x86 output) on all 36 of
  M2-Planet's test programs.

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

Hand-written source above the shared `hex0-seed`, up to a compiler
that can build M2-Planet, counted as raw lines (comments and blank
lines included) with `wc -l`:

| Route                      | Hand-written source                         | Lines |
|----------------------------|---------------------------------------------|------:|
| stage0 AMD64 (canonical)   | hex0 / hex1 / hex2 / catm / M0 sources, `cc_amd64.M1` + its ELF header, defs, libc | 7,628 |
| Forth (this book)          | `000-seed.hex0` + `010-lib.fth` + the 14 `-cc-` files                    | 7,902 |

The stage0 row is the files `AMD64/mescc-tools-seed-kaem.kaem` and
`AMD64/mescc-tools-mini-kaem.kaem` feed in before the first M2
exists:

```sh
git -C vendor/stage0-posix submodule update --init AMD64   # once
cd vendor/stage0-posix/AMD64
wc -l hex0_AMD64.hex0 hex1_AMD64.hex0 hex2_AMD64.hex1 catm_AMD64.hex2 \
      M0_AMD64.hex2 ELF-amd64.hex2 cc_amd64.M1 amd64_defs.M1 libc-core.M1
```

and the Forth row is, from the repository root,

```sh
wc -l 000-seed.hex0 010-lib.fth [0-9][0-9][0-9]-cc-*.fth
```

Neither row counts the tools each route needs to turn M2-Planet's
`.M1` output into an ELF.  stage0 builds `M1` and `hex2` from
mescc-tools' C with its first M2; the Forth route's equivalent is
`130-asm.fth`, another 689 lines.  Nor does the stage0 row count
`kaem-minimal.hex0`, the 406-line script runner stage0 uses to
drive those steps; the Forth route leans on the host shell instead.

Both totals are dominated by the small C compiler at the top.
Ours is `090-cc-emit.fth` through `116-cc-prog.fth`, 4,913 lines of
Forth.  The stage0 one is `cc_amd64.M1`, 5,413 lines of M1 assembly.
Treat the two as the same order of magnitude.

So the audit burden (lines a human has to read) is comparable.
What changes is *the language those lines are in*, and that
matters because:

- An auditor of stage0's route is reading hex columns, M0 macro
  expansions, and M1 assembly.  Mistakes hide as transcription
  errors, off-by-one address arithmetic, and macro-expansion
  surprises.
- An auditor of this book's route is reading hex bytes (for the
  seed only, 1,772 of them) and Forth.  Mistakes hide as
  stack-effect mistakes, wrong primitive choices, and codegen
  template errors.

Different bug surfaces.  An independent path catches bug *classes*
that the canonical path would have made invisible, not just
specific bugs: where the two agree, neither route's
language-specific failure modes are in play.

The 1,772-byte seed is the part that *is* genuinely smaller than
stage0's equivalent intermediate stages.  On the AMD64 path, the
`hex0`, `hex1`, `hex2-0` and `M0` binaries that stage0 builds
before it has an assembler with labels and macros come to 4,054
bytes (229 + 622 + 1,519 + 1,684), and none of them is programmable;
`cc_amd64`, the first thing that compiles C, is 17,309 bytes.  We
get to a programmable layer (a working Forth) in 1,772 bytes because
Forth's primitives are short and the dictionary structure is dense.
To reproduce the stage0 sizes, run the first steps of stage0's
`AMD64/mescc-tools-seed-kaem.kaem` and `mescc-tools-mini-kaem.kaem`
by hand from `vendor/stage0-posix` (after the same `submodule
update` as above):

```sh
D=$(mktemp -d)
bootstrap-seeds/POSIX/AMD64/hex0-seed AMD64/hex0_AMD64.hex0 $D/hex0
$D/hex0   AMD64/hex1_AMD64.hex0 $D/hex1
$D/hex1   AMD64/hex2_AMD64.hex1 $D/hex2-0
$D/hex2-0 AMD64/catm_AMD64.hex2 $D/catm
$D/catm   $D/M0.hex2 AMD64/ELF-amd64.hex2 AMD64/M0_AMD64.hex2
$D/hex2-0 $D/M0.hex2 $D/M0
wc -c $D/hex0 $D/hex1 $D/hex2-0 $D/M0         # 4054 total
$D/M0     AMD64/cc_amd64.M1 $D/cc.hex2
$D/catm   $D/cc0.hex2 AMD64/ELF-amd64.hex2 $D/cc.hex2
$D/hex2-0 $D/cc0.hex2 $D/cc_amd64
wc -c $D/cc_amd64                              # 17309
```

But the *total* source budget above `hex0-seed` is comparable,
because Forth is a means, not a savings.

## Trust roots, plural

The trust root for the Forth route is the union of:

- the 229-byte `hex0-seed` (auditable in an afternoon),
- the Linux kernel (~30 million lines of C, not audited here),
- the x86-64 CPU and its microcode (opaque silicon),
- the host tools that move bytes into the seed: `bash` and `cat`
  everywhere, plus `sed` in the M2-Planet monolith build.

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

Next: [Prologue — Seventeen Hundred and Seventy-Two Bytes](00-prologue.md).
