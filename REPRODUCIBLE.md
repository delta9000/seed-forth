# Reproducible Bootstrap

This document records the bootstrap path from `000-seed.hex0` to a
M2-Planet-compatible compiler output.

## Pinned Upstreams

The repository carries upstreams as submodules:

| Upstream | Submodule path | Commit | Release |
|----------|----------------|--------|---------|
| M2-Planet | `vendor/M2-Planet` | `0a67a6829a0c1d0aedb89e1dc38a7e3ab67592cb` | — |
| mescc-tools | `vendor/mescc-tools` | `9b1375115f9175d876c360dbbfd7e231dd9f2a2f` | — |
| stage0-posix | `vendor/stage0-posix` | `45d90f5955b6907dc6cdea9ebafce558359edcd3` | `Release_1.9.1` |

Initialize them (recursively — `vendor/M2-Planet` has its own nested
`M2libc` submodule, and `vendor/stage0-posix` has its own nested
`bootstrap-seeds` submodule) before running the checks:

```sh
git submodule update --init --recursive
```

The scripts also accept `M2_PLANET`, `MESCC_TOOLS`, `HEX0`, and
`BUILDROOT` environment overrides.  `BUILDROOT` defaults to
`/tmp/seed-bootstrap`; `HEX0` defaults to
`vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed`.

### License notes

The vendored upstreams (`vendor/M2-Planet`, `vendor/mescc-tools`,
`vendor/stage0-posix`) are GPL-3.0-or-later.  The seed-forth source
files at the repository root remain MIT.  Distributions that bundle
the vendored trees must comply with GPLv3+ for those subtrees.
`build.sh` invokes stage0-posix's `hex0-seed` as a tool; the
resulting `seed-forth` binary is the byte-for-byte assembly of
`000-seed.hex0` and is not a derivative work of the assembler.

## Checks

Run from the repository root:

```sh
./build.sh
./test.sh
tests/cc/stage-a-check.sh
```

`stage-a-check.sh` does the essential compiler compatibility check:

1. Build `seed-forth` from `000-seed.hex0`.
2. Build a GCC reference `M2-Planet`.
3. Feed the Forth compiler vocabulary and a M2-Planet monolith to `seed-forth`.
4. Use the resulting `/tmp/cc-out` to compile M2-Planet for `amd64`.
5. Compare that `.M1` output against the GCC-built reference output.

Expected Stage-A result:

```text
stage-a-check: self-v1-amd64.M1 == self-ref-amd64.M1 (2367260 bytes)
stage-a-check: PASS
```

Shared artifact sizes (verified by running `tests/cc/stage-a-check.sh`):

| File | Bytes |
|------|------:|
| `000-seed.hex0` | 27,067 |
| `seed-forth` | 2,040 |
| `cc-out-v1` | 203,241 |
| `self-v1-amd64.M1` | 2,367,260 |

Hashes for the same run:

```text
18bef4a7df46706c1ac9c71d74e9ac252d21200b41a1025ce64c989051decbf6  000-seed.hex0
131bf3ab73917a5a1c39db8114ab5c20f12ca28627f3fdc969ee34d86e41dc74  seed-forth
957ed9d9b1b7aa2a2abfbbf757086dbe2161f0b457b362c492bf78a7f0b4f101  cc-out-v1
22465aa1b4943b830263928f79bb150bbfcbbc1642cfc287b0ed3d873a583d37  self-v1-amd64.M1
```

`build.sh` runs `000-seed.hex0` through stage0-posix's `hex0-seed`
assembler, which strips `;`-line-comments and whitespace before
hex-decoding.  Edits limited to comments leave `seed-forth` (and
every downstream artifact) byte-identical even when the
`000-seed.hex0` hash changes.

The `seed-forth` byte-identity also serves as an independent
cross-check on the bootstrap trust root: stage0-posix's 229-byte
`hex0-seed` and any other hex0-equivalent assembler (xxd, hand-keyed,
etc.) must all produce the same 2040-byte binary.  Disagreement
between two assemblers on this input would be a bug in one of them.

## Stage0 byte-identity (opt-in)

The default `cc-out-v1` is byte-identical to a GCC-built M2-Planet
on the M2-Planet self-host (the canonical Stage-A claim).  It is
**not** byte-identical to an M2-Planet built through the
stage0-posix kaem chain.  The reason is a codegen quirk in
stage0-posix's bootstrap chain: its `cc_amd64` (M0-based) compiler
emits machine code in which the runtime guard

```c
(Architecture & ARCH_FAMILY_X86) && (reg == REGISTER_STACK || reg == REGISTER_ZERO)
```

in `cc_emit.c`'s `write_sub_immediate` and `write_add_immediate`
evaluates `false` for `--architecture amd64`, even though the C
source clearly intends it to be `true` (`AMD64 = 8`,
`ARCH_FAMILY_X86 = 12`, `8 & 12 = 8`).  Every M2-Planet binary
produced through the stage0-posix chain therefore skips the
`sub_rsp,BYTE 'NN'` / `add_rax,BYTE 'NN'` immediate-form
optimization and falls through to the 2-instruction
`mov_r14,%NN; sub_rsp,r14` form.  This is the same M2-Planet
"host-arch nudge" already noted in `bootstrap-chain.sh:198–211`.

To get byte-identity against a stage0-posix-derived M2-Planet,
build `cc-out-v1` with `STAGE0_COMPAT=1`:

```sh
STAGE0_COMPAT=1 ./tests/cc/build-m2planet-monolith.sh
```

This replaces the two guards above with constant `0` in the
M2-Planet monolith before seed-forth compiles it, so the resulting
`cc-out-v1` deliberately omits the same optimization stage0-posix's
chain omits.  Verified outputs:

| Build mode | `cc-out` sha256 | Self-host `.M1` sha256 | Equal to |
|------------|-----------------|------------------------|----------|
| default | `957ed9d9...` | `22465aa1...` | GCC-built M2-Planet reference |
| `STAGE0_COMPAT=1` | (smaller) | `02d98f86...` | stage0-posix-built M2-Planet compiled from the *same* `vendor/M2-Planet` pin |

`STAGE0_COMPAT=1` does **not** make `cc-out-v1` byte-identical to
`vendor/stage0-posix/AMD64/bin/M2-Planet` directly, because
stage0-posix Release_1.9.1 pins M2-Planet at `bd2fe4b0`
(Release_1.13.1) while seed-forth pins `0a67a68`
(Release_1.13.1-30).  The 30-commit source delta accounts for the
remaining ~31 KB diff after `STAGE0_COMPAT` is applied.  Re-running
stage0-posix's kaem chain with seed-forth's `vendor/M2-Planet`
source produces a binary whose output **is** byte-identical to
seed-forth's `cc-out-v1` under `STAGE0_COMPAT=1`.

Neither output is "more correct" than the other — both are valid
M2-Planet emission for the same C input.  The patch exists to
demonstrate that the two paths converge when the codegen quirk is
neutralised, which is the byte-level proof that matters to the
Bootstrappable / Guix Full Source Bootstrap audience.

### Connection to the existing "host-arch nudge"

`STAGE0_COMPAT` is not a new behaviour.  It is the same codegen the
existing `bootstrap-chain.sh` chain reaches naturally at stage v2:

| Path | self-host `.M1` sha256 |
|------|------------------------|
| default cc-out-v1 | `22465aa1...` (uses optimization) |
| default cc-out-v2 (M1+hex2-assembled from v1's output) | `02d98f86...` |
| default cc-out-v3 (M1+hex2-assembled from v2's output) | `02d98f86...` |
| **STAGE0_COMPAT cc-out-v1** | **`02d98f86...`** |
| stage0-posix-derived `m2-cross` (0a67a68 source) | `02d98f86...` |

So `cc-out-v1` under `STAGE0_COMPAT` is byte-identical, at the
compile-output level, to:

- The chain's own v2 / v3 (verified via `cmp /tmp/seed-bootstrap/self-v2-amd64.M1`).
- A stage0-posix-chain-built M2-Planet compiled from the same
  `vendor/M2-Planet` pin source.

Practical consequence: with `STAGE0_COMPAT=1`, the v1 → v2 → v3
fixed-point closes at v1 (`self-v1.M1 == self-v2.M1 == self-v3.M1`),
eliminating the "M2-Planet host-arch nudge" that the default chain
documents at `bootstrap-chain.sh:198–211`.  The nudge is a symptom
of one of the two binaries in the comparison having the optimization
and the other not having it; under `STAGE0_COMPAT`, neither does.

### Verification summary

| Check | Default mode | `STAGE0_COMPAT=1` |
|-------|--------------|--------------------|
| `./test.sh` (seed primitives + lib + cc layers) | PASS | (unchanged — seed is the same) |
| `./tests/cc/stage-a-check.sh` (vs GCC reference) | PASS (`22465aa1...`) | would FAIL by design |
| `bootstrap-chain.sh` Stage 2 fixed-point (v2 == v3) | PASS (`02d98f86...`) | v1 == v2 == v3 (`02d98f86...`) |
| `bootstrap-chain.sh` Stage 3 M2-Planet test parity | 36/36 vs GCC reference | 36/36 vs stage0-derived `m2-cross` |
| `hello.c` end-to-end smoke (Stage G) | PASS (x86 + amd64) | (unchanged structurally) |

## Full Chain

The slower closure check is:

```sh
tests/cc/bootstrap-chain.sh
```

It builds:

1. `cc-out-v1`: seed-forth-compiled M2-Planet-compatible compiler.
2. `self-v1-$ARCH.M1`: output from `cc-out-v1`, compared with the GCC reference.
3. `cc-out-v2-$ARCH`: `self-v1-$ARCH.M1` assembled by M1 + hex2.
4. `self-v2-$ARCH.M1`: self-compile from `cc-out-v2-$ARCH`.
5. `cc-out-v3-$ARCH`: assembled from `self-v2-$ARCH.M1`.
6. `self-v3-$ARCH.M1`: must match `self-v2-$ARCH.M1`.

The default architectures are `x86 amd64`; override with `ARCHES=amd64` or
`ARCHES=x86` for a narrower run.

The final stage compares selected upstream M2-Planet test outputs from
`cc-out-v1` and the GCC-built reference.  Tests that both compilers reject are
counted separately; byte differences or one-sided failures fail the script.

Expected full-chain ending:

```text
M2-Planet tests: identical=36  both-fail=0  differ=0  (of 36)

All stages passed.
```
