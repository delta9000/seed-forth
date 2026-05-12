# Reproducible Bootstrap

This document records the bootstrap path from `000-seed.hex0` to a
M2-Planet-compatible compiler output.

## Pinned Upstreams

The repository carries upstreams as submodules:

| Upstream | Submodule path | Commit |
|----------|----------------|--------|
| M2-Planet | `seed/vendor/M2-Planet` | `0a67a6829a0c1d0aedb89e1dc38a7e3ab67592cb` |
| mescc-tools | `seed/vendor/mescc-tools` | `9b1375115f9175d876c360dbbfd7e231dd9f2a2f` |

Initialize them before running the checks:

```sh
git submodule update --init
```

The scripts also accept `M2_PLANET`, `MESCC_TOOLS`, and `BUILDROOT`
environment overrides.  `BUILDROOT` defaults to `/tmp/seed-bootstrap`.

## Checks

Run from `seed/`:

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

Current shared artifact sizes:

| File | Bytes |
|------|------:|
| `000-seed.hex0` | 26,775 |
| `seed-forth` | 2,040 |
| `cc-out-v1` | 203,241 |
| `self-v1-amd64.M1` | 2,367,260 |

Current hashes for the same Stage-A run:

```text
88c32728eecb3d9fbc31d90e55ea3610aa8a9c894882449c528dcee6e7fc96cf  000-seed.hex0
131bf3ab73917a5a1c39db8114ab5c20f12ca28627f3fdc969ee34d86e41dc74  seed-forth
957ed9d9b1b7aa2a2abfbbf757086dbe2161f0b457b362c492bf78a7f0b4f101  cc-out-v1
22465aa1b4943b830263928f79bb150bbfcbbc1642cfc287b0ed3d873a583d37  self-v1-amd64.M1
```

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
