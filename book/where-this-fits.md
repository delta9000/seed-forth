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
- **Time.**  `./bootstrap.sh` (the GCC-free build) takes about 30 s;
  `./check-all.sh` (build, unit tests, gates, the three book checks,
  Stage A, `bootstrap.sh`, the two pnut checks, and `handoff.sh`'s
  main route) about 90 s; `./verify.sh` (every comparison, plus `stage0-check.sh`
  and the full `handoff.sh`, x86 hand-off included) about 6½ minutes.  All on a 4-core machine;
  yours will differ.
- **What you trust.**  For `./bootstrap.sh`: the 229-byte `hex0-seed`
  from stage0-posix's `bootstrap-seeds` (the only stage0-posix binary
  it runs), this repository's sources, the pinned C and M1 *sources*
  of `vendor/M2-Planet` and `vendor/mescc-tools`, the Linux kernel,
  the CPU, and the host `bash` and `cat`.  `bash` itself drops
  M2-Planet's `#include "..."` lines and duplicate `TRUE`/`FALSE`
  defines while it concatenates the C files, so `sed` is not
  trusted.  (The test script `tests/cc/build-m2planet-monolith.sh`
  does the same filtering with `sed`; `./verify.sh` checks the two
  give the same compiler.)  The script's header states the list
  exactly, and `./handoff.sh`'s header adds what it trusts on top.
- **Where GCC appears.**  Only as a reference, and only in
  `./verify.sh`: Stage A, `bootstrap-chain.sh`'s test-suite parity
  and the `tests/asm` checks build a GCC M2-Planet or GCC mescc-tools
  to compare against, and never run their output as part of the
  chain.  `bootstrap.sh`, `handoff.sh` and `tests/cc/stage0-check.sh`
  use no host C compiler.  (GCC also appears as an *output*: the
  amd64 chain to GCC 15.2 below builds it, with no host compiler.)
  The GCC-free assembler is `130-asm.fth`:
  785 lines of Forth, an M1 expander and hex2 linker, taught in
  Chapter 33; `bootstrap.sh` uses it to build `M1` and `hex2`.
- **Where it stops.**  `bootstrap.sh` stops at a self-hosted
  M2-Planet (`0a67a68`) with its own `M1` and `hex2`.  `./handoff.sh`
  carries on: it feeds those to stage0-posix's own AMD64 recipe in
  place of hex1, hex2, M0 and `cc_amd64`, and the recipe builds all
  19 binaries in stage0-posix's `amd64.answers` byte for byte
  (M2-Planet `bd2fe4b`, blood-elf, M1, hex2, kaem, M2-Mesoplanet,
  mescc-tools-extra).  That is the set live-bootstrap reads at
  stage0-posix's `after.kaem` hook, so from there you continue with
  live-bootstrap as usual.  It does the same for stage0-posix's x86
  recipe (all 19 `x86.answers`), the architecture live-bootstrap
  supports, provided the amd64 kernel also runs 32-bit binaries; a
  pure-i386 machine would need a 32-bit seed.  Nothing here runs
  live-bootstrap itself; `REPRODUCIBLE.md` has the manual steps.
- **Past M2-Planet, to TinyCC.**  The same Forth C compiler builds
  pnut (`vendor/pnut`, unmodified).  Two scripts carry on from there to
  tcc-0.9.27 without GNU Mes: no Mes interpreter, no MesCC and no mes
  libc.  `tests/pnut/sf-pnut-check.sh` uses pnut's own kit, which is
  i386, so its tcc stages need a kernel that runs 32-bit programs.
  `tests/pnut/sf-pnut-amd64-check.sh` is x86-64 from the seed to
  `tcc-boot2 = tcc-boot3` and uses no gcc.  It needs eleven small
  patches to pnut, tcc and pnut's libc, kept in `patches/amd64/`.  Two
  of them fix bugs in tcc-0.9.27's own x86_64 static linking.
  Appendix C has the route.
- **Past TinyCC, to GCC (amd64).**  `gcc64/run-gcc64.sh` carries that
  amd64 `tcc-boot2` on through musl-1.1.24 (tcc and musl rebuilt to a
  fixed point), binutils, gcc-4.0.4 (rebuilt to a fixed point),
  gcc-4.7.4 and gcc-10.5.0 to GCC 15.2.0, whose own three-stage
  bootstrap ends with stage 2 = stage 3.  Every compiler, assembler and
  linker in it is built by the stage before it; a guard refuses any
  host one.  It still runs host build glue (bash, make, sed, coreutils,
  tar, xz, patch, python3 for one text substitution), uses host bison
  and m4 to generate gcc-4.0.4's parser and lexer, and trusts the
  source tarballs' pregenerated `configure` scripts.  It takes about
  1.5 hours on 4 cores, so only `./verify.sh` runs it, and only when
  asked (`VERIFY_GCC64=1`).  `gcc64/README.md` has the stages, pins and
  trust statement.

  The prior-art research for this project found other Mes-free routes
  to TinyCC that go through a small C compiler: pnut's kit and
  cosinusoidally's tcc_simple / tcc_bootstrap_alt.  All of them are
  i386-only.  The amd64 routes it found reach TinyCC by other means.
  blynn-bootstrap goes through a C compiler written in Haskell and uses
  mes libc.  pommicket/bootstrap goes through its own non-C languages
  from its own seed.  That research was a survey of public repositories
  in September 2026, not an exhaustive search.

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
        │   ◄── THE ONLY STAGE0 BINARY bootstrap.sh   │
        │       RUNS                                  │
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
quicker to build than running stage0.  Against a stage0-built one
the first-generation `.M1` differs, in add/sub-immediate forms
only (`stage0-check.sh` checks every changed line): M2-Planet's source guards a short instruction form
with `&&`, which our compiler (like GCC) evaluates as ISO C does and
M2-Planet compiles as a bitwise `and`.  One generation later the
routes meet (see the list below).

Once you have the Forth route's M2-Planet you can get back onto the
canonical chain: `./handoff.sh` feeds it, with the Forth route's
`M1` and `hex2`, to stage0-posix's own recipe from the point where
stage0 has its first M2-Planet, and the recipe produces the same 19
binaries stage0-posix publishes hashes for.  So the Forth route is
both an independent cross-check on stage0's stretch from `hex1` to
M2-Planet and, on an amd64 kernel, a drop-in replacement for it, for
stage0's AMD64 recipe and (with the kernel's 32-bit support) its x86
one.

## What "working" actually means here

A paranoid auditor can pick which route to trust as their entry
into the Bootstrappable chain:

- **Trust the stage0 route.**  Read stage0-posix's hex and M1.  Run
  its hex1/hex2/M0/`cc_amd64` pipeline.  Get M2-Planet.
- **Trust the Forth route.**  Read this book.  Run
  `000-seed.hex0` through any hex0 assembler.  Get seed-forth.
  Load the nineteen `.fth` files.  Get an M2-Planet-equivalent.

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
- **Diverse double-compiling** (`tests/cc/stage0-check.sh`, amd64):
  stage0-posix's recipe rebuilds M2-Planet `0a67a68` twice over,
  once from stage0's route (`cc_amd64` → `M2` → `x1` → `x2`) and
  once from ours (seed-forth → our C compiler → `cc-out-v1` → `y1`
  → `y2`).  `y2` and `x2` are the same binary, byte for byte.  A
  second pass links each side only with its own `M1`, `hex2` and
  `blood-elf` (ours built by the Forth route, stage0's by stage0) and
  gets the same binary again, and the same rebuilt `M1`, `hex2` and
  `blood-elf`.  No binary is shared from the seed on; the two runs
  still share the `hex0-seed` file, the M2-Planet, mescc-tools and
  M2libc sources, the kernel and bash.
- **Hand-off** (`./handoff.sh`, amd64 and x86): the Forth route
  standing in for stage0's hex1/hex2/M0/`cc_amd64` phases drives
  stage0-posix's own recipe to all 19 `amd64.answers` hashes,
  M2-Planet `bd2fe4b` included, and, cross-targeting i386, its x86
  recipe to all 19 `x86.answers` hashes; here nothing from stage0's
  hex/M0/`cc_*` phases runs, and the Forth route's `M1` and `hex2`
  link the first tools.
- **`STAGE0_COMPAT=1`**: switching those two `&&` guards off makes the
  Forth-built compiler's self-compile `.M1` match a stage0-built
  M2-Planet's one generation early (see `REPRODUCIBLE.md`).  A
  shortcut; the two results above do not need it.
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
above, not on every C program.  And its main chain stops where
stage0-posix stops.  The pnut checks go one rung further, to TinyCC
without Mes, and on amd64 `gcc64/run-gcc64.sh` goes on to GCC 15.2
with no host compiler, assembler or linker.  That last leg is not a
full source bootstrap, though.  It runs host build glue that
Live-Bootstrap builds from source (make, bash, coreutils, bison, m4,
...), it trusts pregenerated `configure` scripts that Live-Bootstrap
regenerates, and its GCC has not been compared with Live-Bootstrap's.
For a full source bootstrap to GCC, Live-Bootstrap's road is still
the established one.

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
| Forth (this book)          | `000-seed.hex0` + `010-lib.fth` + the 18 `-cc-` files                    | 11,507 |

The Forth total includes the opt-in direct-TinyCC extension now loaded
with the numbered compiler files; the legacy default is unchanged.

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
`130-asm.fth` (Ch 33), another 785 lines.  Nor does the stage0 row count
`kaem-minimal.hex0`, the 406-line script runner stage0 uses to
drive those steps; the Forth route leans on the host shell instead.

Both totals are dominated by the small C compiler at the top.
Ours is `090-cc-emit.fth` through `116-cc-prog.fth`, 7,058 lines of
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
  (`bootstrap.sh` needs nothing else; the test scripts also use
  `sed` to build the M2-Planet monolith).

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
