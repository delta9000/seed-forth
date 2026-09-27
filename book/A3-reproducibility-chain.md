# Appendix C — Reproducibility: the full hex0 → seed → M2-Planet chain

The bootstrap story is auditable end-to-end: every link in this
chain produces byte-identical output from byte-identical input,
and every link's source is human-readable in this repository or
in a vendored upstream.

This appendix walks the chain from the trust-root assembler
(`hex0-seed` from stage0-posix, 229 bytes) up to the byte-identity
proof against M2-Planet built with GCC.  Each stage names the
exact command and the artifact it produces.

The book proper covers the *middle* of this chain: the seed-Forth
binary at one end and the C compiler's M2-Planet self-compile
output at the other.  The links *before* and *after* are mentioned
in passing in the prologue and Ch 32; this appendix consolidates
them.

## The chain at a glance

The same chain in tabular form.  Each row is one rung; the
"Verification" column is the command that proves the rung holds,
and the "GCC?" column says whether GCC is anywhere in the
provenance of that row's output.  Only the reference outputs in
rows A and 3 have GCC in them, and they are only ever compared
against.

| Stage | Input | Tool / producer | Output | GCC? | Runs on | Verification | Trust notes |
|---|---|---|---|---|---|---|---|
| 0 | `000-seed.hex0` (41,293 bytes annotated; 1,772 machine bytes) | stage0-posix's 229-byte `hex0-seed` | `seed-forth` (1,772-byte x86-64 ELF) | no | Linux x86-64 | `wc -c seed-forth` → `1772`; `sha256sum` matches `697e340e…` | `hex0-seed` is externally trusted; any hex0-equivalent assembler reproduces the same bytes. |
| 1 | `seed-forth` + `010-lib.fth` | the seed Forth, extending itself | extended Forth in memory | no | same host | `./test.sh` | Self-hosted from seed primitives; no external compiler.  The source goes in as written: the seed's reader skips Forth comments itself, so no text tool sits between the file and the seed. |
| 2 | extended Forth + `020-cc-arena.fth` … `120-cc-main.fth` + M2-Planet monolith C source | `seed-forth` running the compiler vocabulary | `cc-out-v1` (`/tmp/cc-out`, ~203 KB ELF) | no | same host | `[ -x /tmp/cc-out ]` and a smoke run | All compiler code is Forth source loaded by the seed; the monolith is built by `build-m2planet-monolith.sh` (with `sed`) or by `bootstrap.sh` (in bash). |
| M | mescc-tools' `M1` and `hex2` C sources | M2-Planet built from `cc-out-v1`'s output, then the Forth assembler `130-asm.fth` | `M1`, `hex2` | no | same host | `./bootstrap.sh` (they must rebuild themselves byte for byte); `./verify.sh` compares them with GCC-built mescc-tools | The assembler every later row uses. |
| A | `cc-out-v1` and `m2-ref` (GCC-built M2-Planet) | each compiles the M2-Planet source set | `self-v1-amd64.M1` and `self-ref-amd64.M1` (2,367,260 bytes) | v1: no; ref: yes | same host | `cmp` — exits 0 iff byte-identical | Cross-validation: two independently built M2-Planet binaries must agree on output. |
| B | `self-v1-amd64.M1` | `M1` + `hex2` from row M | `cc-out-v2-amd64` (assembled binary) | no | same host | `bootstrap.sh`, `bootstrap-chain.sh` run it | M2-Planet assembled by assemblers that came out of this same chain. |
| C | `tiny.c` (`int main() { return 42; }`) | `cc-out-v1` and `cc-out-v2-amd64` | `tiny-v1-amd64.M1`, `tiny-v2-amd64.M1` | no | same host | `cmp` — fails the script on mismatch | Sanity check that v2 works before trusting it with a self-compile. |
| D | `cc-out-v2-amd64` + M2-Planet sources | `cc-out-v2-amd64` self-compiles | `self-v2-amd64.M1` | no | same host | none — the script only reports whether it equals `self-v1-amd64.M1`; it never fails here.  Expected sha256 in default mode is `02d98f86…` (recorded, not checked) | Differs from v1's `.M1` by design: v1 takes the `sub_rsp, imm` optimization (see "Expected hashes" below). |
| E–F | `self-v2-amd64.M1` re-assembled into `cc-out-v3-amd64`, which self-compiles | `M1` + `hex2`, then the compiler again | `self-v3-amd64.M1` | no | same host | `cmp self-v2-amd64.M1 self-v3-amd64.M1` → 0 | Fixed-point closure: v3 must equal v2 byte for byte. |
| G | `hello.c` | `cc-out-v3-amd64`, then `M1` + `hex2` | `hello-amd64-elf` | no | same host | stdout is exactly `Hello from Forth-bootstrapped M2-Planet!` and exit code 0 | End-to-end smoke. |
| 3 | every `test/test*/` program in M2-Planet | `cc-out-v1` and `m2-ref`, `--architecture x86` | one output per test from each | v1: no; ref: yes | same host | each test: both outputs byte-identical, or both compilers reject it; anything else fails the script | Parity beyond the self-compile, on M2-Planet's own test suite. |

Stage A, *byte-identity against the GCC reference*, is the
proof the book builds toward.  `./bootstrap.sh` runs rows 0–2, M,
B and D–G for amd64 with no GCC anywhere (next section).
`tests/cc/bootstrap-chain.sh` runs `bootstrap.sh`, then A–G once per
architecture (`x86` and `amd64` by default; the table shows the
amd64 names), then the Stage-3 test-suite parity once.
`./verify.sh` runs every comparison against a GCC-built reference.

## The GCC-free build

```sh
./bootstrap.sh
```

One script, about 30 seconds on amd64 Linux, from the 229-byte
`hex0-seed` to a self-hosted M2-Planet.  It builds `seed-forth`;
`cc-out-v1` (M2-Planet compiled by the Forth compiler); `M1` and
`hex2` (mescc-tools, compiled by M2-Planet and assembled by
`130-asm.fth`); then `cc-out-v2` and `cc-out-v3`, M2-Planet
assembled by those `M1` and `hex2` from its own output.  It fails
unless v2 and v3 compile M2-Planet to the same `.M1` (the fixed
point), `M1` and `hex2` rebuild themselves byte for byte, and a
`hello.c` built by v3 runs; then it prints the SHA-256 of each
artifact in `build-out/out/`.

What it trusts: `hex0-seed`, this repository's `.hex0` and `.fth`
files, the pinned C and M1 *sources* under `vendor/M2-Planet` and
`vendor/mescc-tools` (no binary from them runs), the Linux kernel,
and the host `bash` and `cat`.  `bash` also does the one text
edit on M2-Planet's source that the `sed` in
`build-m2planet-monolith.sh` does (dropping its `#include "..."`
lines), so `sed` is not trusted.  No host C compiler, assembler or
linker runs, and nothing is compared with a GCC-built binary; that
is `./verify.sh`'s job.  The script's header lists the trust base
exactly, and `REPRODUCIBLE.md` records the hashes.

For a wider-angle dataflow picture (showing where this rung sits
inside the Bootstrappable / Full Source Bootstrap ladder),
[Where this fits](where-this-fits.md) has the ladder diagram.
The rest of this appendix is operator-facing: the exact commands
that turn each row of the table above into a verifiable artifact.

## Reproducing each stage

All commands run from the repository root.

### Stage 0 — assemble the seed

```sh
./build.sh
```

What this does: invokes `vendor/stage0-posix/.../hex0-seed
000-seed.hex0 seed-forth`, producing a 1,772-byte ELF executable.

Expected output:
```
Built seed-forth (1772 bytes) using vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
```

Sanity check:
```sh
wc -c seed-forth      # 1772
file seed-forth       # ELF 64-bit LSB executable, x86-64
```

### Stage 1 — run the Forth and library tests

```sh
./test.sh
```

What this does: feeds curated input to `./seed-forth` and checks
exit codes and stdout.  Includes the literate-program tangle
verifier (`tools/tangle.sh verify`), all seed primitives, the
`010-lib.fth` definitions, and the REPL paths.

Expected: every line prints `PASS:`; final exit code 0.

### Stage 2 — compile M2-Planet with seed-forth's C compiler

```sh
./tests/cc/build-m2planet-monolith.sh
```

What this does: concatenates M2-Planet's `.c` source files into a
single monolith (stripping `#include "..."` lines since the
preprocessor has no `#ifndef`/`#endif`), then pipes it through
`seed-forth` loading `010-lib.fth` through `120-cc-main.fth`.  The
Forth files are `cat`'d straight in, comments and all; the seed's
reader skips `\` and `( )` comments itself (Ch 17).  The only text
tool in this stage is the `sed` that edits the C monolith's
`#include` lines, and it never touches the Forth.
The output is `/tmp/cc-out` — an x86-64 ELF binary that is
itself a working M2-Planet-compatible C compiler.

Sanity check:
```sh
[ -x /tmp/cc-out ] && echo "compiled"
```

### Stage A — the byte-identity proof

```sh
./tests/cc/stage-a-check.sh
```

What this does:

1. builds `cc-out-v1` from Stage 2 above (rebuilt on every run);
2. builds `m2-ref` with GCC from `vendor/M2-Planet`
   (`tests/cc/build-gcc-refs.sh`, also rebuilt on every run, so a
   stale reference is never reused);
3. runs both compilers on the *same* M2-Planet source set;
4. diffs the resulting `.M1` files.

Expected output (the byte count is the size of the emitted `.M1`):
```
stage-a-check: self-v1-amd64.M1 == self-ref-amd64.M1 (2367260 bytes)
stage-a-check: PASS
```

A single byte of difference fails the check and exits non-zero.

### Stage B–G — the full fixed-point bootstrap

```sh
./tests/cc/bootstrap-chain.sh
```

What this does: runs `./bootstrap.sh` for `cc-out-v1`, `M1` and
`hex2`, so no binary in the chain has GCC in its provenance.  Then,
for each architecture in `ARCHES` (default
`x86 amd64`), it runs stage A again, then B (M1+hex2 assemble v1's
output → `cc-out-v2`), C (v1 and v2 must compile `tiny.c` to the
same `.M1`), D (v2 self-compiles; the difference from v1's `.M1`
is printed, not failed), E–F (v3 = v2's self-compile assembled;
v3's self-compile must equal v2's byte-for-byte — the fixed
point), and G (v3 compiles `hello.c`, M1+hex2 link it, and the
result must print `Hello from Forth-bootstrapped M2-Planet!` and
exit 0).  Then Stage 3 compiles every program in M2-Planet's test
suite with v1 and with the GCC reference at `--architecture x86`;
each must give byte-identical output or be rejected by both.

This script takes a little over a minute and exercises the full chain.

## Expected hashes

The four hashes that prove a reproducer matched the canonical run.
Reproduced on the reviewer's machine and recorded in
`REPRODUCIBLE.md`.

### Stage 0 and Stage A (default mode)

```text
16c09d3a841fb5e62b115f225361f3006075a4998f46966d83e21d991e159e8e  000-seed.hex0
697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e  seed-forth
025208db31342c4070dbcd3b72f56ddfdde7d38c582c96ea9fdc59bcc6ef7d1e  cc-out-v1
22465aa1b4943b830263928f79bb150bbfcbbc1642cfc287b0ed3d873a583d37  self-v1-amd64.M1
```

`build.sh` runs `000-seed.hex0` through stage0-posix's 229-byte `hex0-seed`
assembler, which strips `;`-line-comments and whitespace before
hex-decoding.  Edits limited to comments leave `seed-forth` (and
every downstream artifact) byte-identical even when the
`000-seed.hex0` hash changes.  The `seed-forth` hash is therefore
the reproducer checkpoint that matters for Stage 0.

### Stages B–F (default mode, from `bootstrap-chain.sh`)

| Path | self-host `.M1` sha256 |
|---|---|
| `cc-out-v1` (uses the `sub_rsp, imm` optimization) | `22465aa1…` |
| `cc-out-v2` (M1+hex2-assembled from v1's output) | `02d98f86…` |
| `cc-out-v3` (M1+hex2-assembled from v2's output) | `02d98f86…` |

The fixed point closes between v2 and v3: assembling v2's output
and re-self-compiling reproduces v2's `.M1` byte for byte.

### `STAGE0_COMPAT=1` mode

Building `cc-out-v1` with `STAGE0_COMPAT=1` reproduces a
stage0-posix-derived M2-Planet binary's `.M1` output instead of
GCC's:

| Mode | `self-v1-amd64.M1` sha256 | Equal to |
|---|---|---|
| default | `22465aa1…` | GCC-built M2-Planet reference |
| `STAGE0_COMPAT=1` | `02d98f86…` | stage0-posix-derived M2-Planet *and* the default mode's `cc-out-v2`/`v3` |

The mode is explained at length in `REPRODUCIBLE.md`.  In short,
M2-Planet's `cc_emit.c` guards two short add/sub-immediate forms with
`(Architecture & ARCH_FAMILY_X86) && (reg == ...)`.  Our compiler,
like GCC, reads `&&` as ISO C does, so the guard is `8 && 1`, true,
and `cc-out-v1` emits the short forms.  M2-Planet compiles `&&` as a
bitwise `and`, so any M2-Planet-built M2-Planet (stage0's, or our own
v2 and v3) computes `8 & 1`, false, and never does.  Nothing in
stage0 is at fault; the difference is in M2-Planet's source.
`STAGE0_COMPAT=1` rewrites those two guards to `0`, so `cc-out-v1`
behaves like an M2-Planet-built M2-Planet and the fixed point closes
at v1 instead of at v2.  It is a shortcut: the cross-check below
does not need it.

## Cross-check against stage0-posix (diverse double-compiling)

```sh
tests/cc/stage0-check.sh      # amd64 only; about 60 s; no host C compiler
```

It needs stage0-posix's nested submodules (the script's header gives
the one-time `git submodule update` line) and skips with exit 77
without them.  It runs stage0-posix's own AMD64 chain from its seeds
(all 19 binaries must match `amd64.answers`), then rebuilds
M2-Planet `0a67a68` with stage0's Phase-15 recipe twice over from two
starting compilers:

- stage0 route: `cc_amd64` → `artifact/M2` → `x1` → `x2`;
- Forth route: seed-forth → our C compiler → `cc-out-v1` → `y1` → `y2`.

`y2 == x2`, byte for byte (`6008773d…`), with no `STAGE0_COMPAT`:
one generation after `cc-out-v1`, the Forth-rooted and the
stage0-rooted chains reach the same M2-Planet binary.  In that stage
stage0's `M1`, `hex2` and `blood-elf` link both routes' outputs, so
it shows only that the compiler lineages agree.  Stage 4b removes the
shared tools: the Forth side links only with `bootstrap.sh`'s `M1`
and `hex2` and a `blood-elf` compiled by `cc-out-v3`, the stage0 side
only with stage0's own.  Still `f2 == x2` (`6008773d…`), and the two
routes' M2-Planets, each linked by its own tools, rebuild
byte-identical `M1`, `hex2` and `blood-elf`.  No binary is shared
from the seed on.  What the two still share: the `hex0-seed` file
(each runs it on a different input), the M2-Planet, mescc-tools and
M2libc *sources* (M2libc's `.M1` definitions and ELF headers
included), the Linux kernel and bash.  It covers amd64 only.

## Handing off to stage0-posix's recipe, and to live-bootstrap

```sh
./handoff.sh                  # amd64 + x86; about 4½ min; no host C compiler
ARCHES=amd64 ./handoff.sh     # amd64 only; about 75 s
```

`handoff.sh` takes `bootstrap.sh`'s outputs and puts them where
stage0-posix's hex1 → hex2 → M0 → `cc_amd64` → `M2` stretch would
have put its own: v3 compiles stage0's Phase-5 input (M2-Planet
`bd2fe4b`) into `artifact/M2`, and the Forth route's `M1` and `hex2`
stand in for `M0` and `hex2-0`.  Then it runs stage0-posix's recipe
from Phase 6 on, unchanged.  All 19 binaries match stage0-posix's
`amd64.answers`, including `bin/M2-Planet` (`7cf19de2…`).  Of stage0-posix's seed
binaries only `hex0-seed` runs, and none of hex1, hex2-0, catm, M0,
`cc_amd64` or stage0's own `M2` is built.  Using `cc-out-v2`
itself as `artifact/M2` gives 12 of 19 (M2-Planet `0a67a68` generates
different code from `bd2fe4b`), and all 19 one generation later.

The same works for stage0-posix's x86 (i386) recipe.  The amd64
Forth-route tools cross-target: v3 compiles the x86 Phase-5 input
with `--architecture x86`, and `M1`/`hex2` link it into an i386
`artifact/M2`.  stage0-posix's x86 recipe then runs from Phase 6, and
all 19 binaries match `x86.answers` (`x86/bin/M2-Planet` is
`f4267292…`).  From Phase 6 on every binary is 32-bit, so the kernel
must run i386 programs: an x86-64 kernel with IA-32 emulation, which
the script tests first, skipping x86 when it is missing.  The seed
itself is x86-64, so this needs a machine that runs both; a pure-i386
machine would need a 32-bit port of the seed, `010-lib.fth`'s system
calls and the C compiler's back end (`REPRODUCIBLE.md` lists what that
involves).

live-bootstrap starts from that same stage0-posix pin and takes over
at stage0-posix's `after.kaem` hook, reading `/AMD64/bin`.  With a
byte-identical `AMD64/bin` (or `x86/bin`, live-bootstrap's one
supported architecture), the rest is "continue with live-bootstrap as
usual"; the manual steps are in `REPRODUCIBLE.md`.

## Past M2-Planet: pnut and TinyCC

The compiler this book builds also compiles pnut, unmodified
(Ch 32 §5).  `tests/pnut/sf-pnut-check.sh` checks that the pnut it
builds generates, for pnut's TinyCC kit, the same `pnut-exe` as a pnut
built by `bootstrap.sh`'s M2-Planet (sha256 `19d96d9e…`), and with
`SF_PNUT_TCC=1` runs the kit on to tcc-0.9.27, whose `tcc-boot2` and
`tcc-boot3` must equal pnut's published `03e96a1a…`.  `REPRODUCIBLE.md`
("Past M2-Planet") has the configuration and the full hashes.

## What "byte-identical" means here

The `.M1` files compared in Stage A are *textual* M1 assembly
(mescc-tools format), not raw ELF.  Byte-identity at the M1 stage
is equivalent to byte-identity at the eventual ELF stage, because
M1 + hex2 are deterministic.

Why M1 is the comparison point: the two compiler *binaries* are
different by design.  `cc-out-v1` is an ELF laid out by our Forth
compiler; `m2-ref` is an ELF laid out by GCC.  Comparing them would
fail on the first byte and prove nothing.  What can agree is what
they *emit*.  So the check is indirect: our Forth compiler built
`cc-out-v1` from M2-Planet's source, and if `cc-out-v1` then emits
the same `.M1` as `m2-ref` on the same input, our compiler
translated M2-Planet faithfully, at least on every code path that
input exercises.

## What the chain proves and does not prove

It proves: starting from 229 bytes of hex0 assembler (the
stage0-posix trust root), you can build a 1,772-byte Forth, use it
to compile the M2-Planet C compiler (8,479 lines across the 11
files of the self-compile source set), and the resulting binary
produces byte-identical M1 output to GCC-built M2-Planet on
M2-Planet's own sources and test suite.  And, by `bootstrap.sh`
alone, that the same 229 bytes plus source reach a self-hosted
M2-Planet with its own `M1` and `hex2` at a byte-identical fixed
point, with no GCC-built binary run anywhere.  Every byte is
auditable.

With `stage0-check.sh` and `handoff.sh`, it also shows that this
route and stage0-posix's reach the same M2-Planet binary one
generation later, also when each route links with its own tools, and
that the Forth route can drive stage0-posix's own recipes to their
published `amd64.answers` and `x86.answers` (the x86 one on an amd64
kernel with IA-32 emulation).

It does *not* prove: that the resulting compiler is bug-free, that
M2-Planet is bug-free, that the kernel running this is not
compromised, or that the broader Guix Full Source Bootstrap chain
beyond M2-Planet is auditable.  See `REPRODUCIBLE.md` for the
caveats, the hand-off details and the `STAGE0_COMPAT` shortcut.

The chain is *one segment* of a larger one.  See
[bootstrappable.org](https://bootstrappable.org) for the rest.
