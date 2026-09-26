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
"Verification" column is the command that proves the rung holds.

| Stage | Input | Tool / producer | Output | Runs on | Verification | Trust notes |
|---|---|---|---|---|---|---|
| 0 | `000-seed.hex0` (27,002 bytes annotated; 2,040 machine bytes) | stage0-posix's 229-byte `hex0-seed` | `seed-forth` (2,040-byte x86-64 ELF) | Linux x86-64 | `wc -c seed-forth` → `2040`; `sha256sum` matches `131bf3ab…` | `hex0-seed` is externally trusted; any hex0-equivalent assembler reproduces the same bytes. |
| 1 | `seed-forth` + `010-lib.fth` | the seed Forth, extending itself | extended Forth in memory | same host | `./test.sh` | Self-hosted from seed primitives; no external compiler. |
| 2 | extended Forth + `020-cc-arena.fth` … `120-cc-main.fth` + M2-Planet monolith C source | `seed-forth` running the compiler vocabulary | `cc-out-v1` (`/tmp/cc-out`, ~203 KB ELF) | same host | `[ -x /tmp/cc-out ]` and a smoke run | All compiler code is Forth source loaded by the seed; the monolith is built by `build-m2planet-monolith.sh`. |
| A | `cc-out-v1` and `m2-ref` (GCC-built M2-Planet) | each compiles the M2-Planet source set | `self-v1-amd64.M1` and `self-ref-amd64.M1` (2,367,260 bytes) | same host | `cmp` — exits 0 iff byte-identical | Cross-validation: two independently built M2-Planet binaries must agree on output. |
| B | `self-v1-amd64.M1` | `M1` + `hex2` from mescc-tools | `cc-out-v2-amd64` (assembled binary) | same host | `bootstrap-chain.sh` runs it | Exercises the mescc-tools link in the canonical chain. |
| C | `tiny.c` (`int main() { return 42; }`) | `cc-out-v1` and `cc-out-v2-amd64` | `tiny-v1-amd64.M1`, `tiny-v2-amd64.M1` | same host | `cmp` — fails the script on mismatch | Sanity check that v2 works before trusting it with a self-compile. |
| D | `cc-out-v2-amd64` + M2-Planet sources | `cc-out-v2-amd64` self-compiles | `self-v2-amd64.M1` | same host | none — the script only reports whether it equals `self-v1-amd64.M1`; it never fails here.  Expected sha256 in default mode is `02d98f86…` (recorded, not checked) | Differs from v1's `.M1` by design (the host-arch nudge, below). |
| E–F | `self-v2-amd64.M1` re-assembled into `cc-out-v3-amd64`, which self-compiles | `M1` + `hex2`, then the compiler again | `self-v3-amd64.M1` | same host | `cmp self-v2-amd64.M1 self-v3-amd64.M1` → 0 | Fixed-point closure: v3 must equal v2 byte for byte. |
| G | `hello.c` | `cc-out-v3-amd64`, then `M1` + `hex2` | `hello-amd64-elf` | same host | stdout is exactly `Hello from Forth-bootstrapped M2-Planet!` and exit code 0 | End-to-end smoke. |
| 3 | every `test/test*/` program in M2-Planet | `cc-out-v1` and `m2-ref`, `--architecture x86` | one output per test from each | same host | each test: both outputs byte-identical, or both compilers reject it; anything else fails the script | Parity beyond the self-compile, on M2-Planet's own test suite. |

Stage A — *byte-identity against the GCC reference* — is the
proof the book builds toward.  `tests/cc/bootstrap-chain.sh` runs
A–G once per architecture (`x86` and `amd64` by default; the table
shows the amd64 names), then the Stage-3 test-suite parity once.

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
000-seed.hex0 seed-forth`, producing a 2,040-byte ELF executable.

Expected output:
```
Built seed-forth (2040 bytes) using vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
```

Sanity check:
```sh
wc -c seed-forth      # 2040
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
`seed-forth` loading `010-lib.fth` through `120-cc-main.fth`.
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

1. builds `cc-out-v1` from Stage 2 above (cached if present);
2. builds `m2-ref` via `make` in `vendor/M2-Planet` (GCC builds the
   reference);
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

What this does: for each architecture in `ARCHES` (default
`x86 amd64`), runs stage A again, then B (M1+hex2 assemble v1's
output → `cc-out-v2`), C (v1 and v2 must compile `tiny.c` to the
same `.M1`), D (v2 self-compiles; the difference from v1's `.M1`
is printed, not failed), E–F (v3 = v2's self-compile assembled;
v3's self-compile must equal v2's byte-for-byte — the fixed
point), and G (v3 compiles `hello.c`, M1+hex2 link it, and the
result must print `Hello from Forth-bootstrapped M2-Planet!` and
exit 0).  Then Stage 3 compiles every program in M2-Planet's test
suite with v1 and with the GCC reference at `--architecture x86`;
each must give byte-identical output or be rejected by both.

This script takes longer (minutes) and exercises the full chain.

## Expected hashes

The four hashes that prove a reproducer matched the canonical run.
Reproduced on the reviewer's machine and recorded in
`REPRODUCIBLE.md`.

### Stage 0 and Stage A (default mode)

```text
662ae174fd6c77909dbbfb275fc8b2aa5dda8608eac54f0e39ffc12ad5c12f2c  000-seed.hex0
131bf3ab73917a5a1c39db8114ab5c20f12ca28627f3fdc969ee34d86e41dc74  seed-forth
957ed9d9b1b7aa2a2abfbbf757086dbe2161f0b457b362c492bf78a7f0b4f101  cc-out-v1
22465aa1b4943b830263928f79bb150bbfcbbc1642cfc287b0ed3d873a583d37  self-v1-amd64.M1
```

`build.sh` runs `000-seed.hex0` through stage0-posix's 229-byte `hex0-seed`
assembler, which strips `;`-line-comments and whitespace before
hex-decoding.  Edits limited to comments leave `seed-forth` (and
every downstream artifact) byte-identical even when the
`000-seed.hex0` hash changes.  The `seed-forth` hash is therefore
the load-bearing reproducer checkpoint for Stage 0.

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

The mode is explained at length in `REPRODUCIBLE.md`; in short, it
disables one codegen optimization that stage0-posix's `cc_amd64`
already skips, so the fixed point closes at v1 instead of at v2.

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
translated M2-Planet faithfully — at least on every code path that
input exercises.

## What the chain proves and does not prove

It proves: starting from 229 bytes of hex0 assembler (the
stage0-posix trust root), you can build a 2,040-byte Forth, use it
to compile the M2-Planet C compiler (8,479 lines across the 11
files of the self-compile source set), and the resulting binary
produces byte-identical M1 output to GCC-built M2-Planet on
M2-Planet's own sources and test suite.  Every byte is
auditable.

It does *not* prove: that the resulting compiler is bug-free, that
M2-Planet is bug-free, that the kernel running this is not
compromised, or that the broader Guix Full Source Bootstrap chain
beyond M2-Planet is auditable.  See `REPRODUCIBLE.md` for the
caveats and the stage0-byte-identity option.

The chain is *one segment* of a larger one.  See
[bootstrappable.org](https://bootstrappable.org) for the rest.
