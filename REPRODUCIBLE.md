# Reproducible Bootstrap

This document records the bootstrap path from `000-seed.hex0` to a
M2-Planet-compatible compiler output.

For a reader-facing walk-through with diagrams and one paragraph per
stage, see **[Appendix C of the book](book/A3-reproducibility-chain.md)**.
This file is the operator-facing companion: exact submodule pins,
SHA-256 hashes, license notes, and the `STAGE0_COMPAT=1` opt-in for
matching stage0-posix's M2-Planet codegen byte-for-byte.

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
`./build-out` for `bootstrap.sh`, `./build-out/verify` for `verify.sh`,
and `/tmp/seed-bootstrap` for the individual `tests/` scripts; `HEX0`
defaults to `vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed`.
No script reuses a binary left in its `BUILDROOT` by an earlier run:
`bootstrap.sh` and `verify.sh` wipe their output directories, and the
GCC references are rebuilt from source on every run by
`tests/cc/build-gcc-refs.sh` (GCC output is not reproducible across GCC
versions, so a pinned hash would not work; the rebuild takes ~1 s).

### License notes

The vendored upstreams (`vendor/M2-Planet`, `vendor/mescc-tools`,
`vendor/stage0-posix`) are GPL-3.0-or-later.  The seed-forth source
files at the repository root remain MIT.  Distributions that bundle
the vendored trees must comply with GPLv3+ for those subtrees.
`build.sh` invokes stage0-posix's `hex0-seed` as a tool; the
resulting `seed-forth` binary is the byte-for-byte assembly of
`000-seed.hex0` and is not a derivative work of the assembler.

## GCC-free build

```sh
./bootstrap.sh                 # amd64 Linux; ~30 s; BUILDROOT=... to move ./build-out
```

This is the whole chain with no GCC in the provenance of any output,
and with no comparison against any GCC-built binary:

| Step | Built by | Output (`$BUILDROOT/out/`) |
|------|----------|----------------------------|
| 1 | `hex0-seed` (229 bytes, stage0-posix) from `000-seed.hex0` | `seed-forth` |
| 2 | `seed-forth` + `010-lib.fth` + `020`–`120-cc-*.fth`, from the M2-Planet monolith | `cc-out-v1` |
| 3 | `cc-out-v1` on M2-Planet; then `130-asm.fth` on that `.M1` | `self-v1-amd64.M1`, `cc-out-v2-fasm` |
| 4 | `cc-out-v2-fasm` on mescc-tools' C; then `130-asm.fth` | `M1`, `hex2` |
| 5 | `M1` + `hex2` on `self-v1-amd64.M1` — must equal `cc-out-v2-fasm` | `cc-out-v2` |
| 6 | `cc-out-v2` on M2-Planet, `M1` + `hex2`, then `cc-out-v3` on M2-Planet | `self-v2-amd64.M1`, `cc-out-v3`, `self-v3-amd64.M1` |

It fails unless `self-v2-amd64.M1 == self-v3-amd64.M1` (the
self-hosting fixed point), `cc-out-v3` plus `M1`+`hex2` rebuild `M1`
and `hex2` byte for byte, and a `hello.c` compiled by v3 runs.

It trusts: `hex0-seed`; this repository's `.hex0`/`.fth` sources; the
pinned C and M1 sources of `vendor/M2-Planet` and `vendor/mescc-tools`
(including their `M2libc`; no binary from those trees runs); the Linux
kernel; and the host `bash` and `cat`.  The M2-Planet monolith is
filtered by a bash `while read` loop, not `sed`: it drops M2-Planet's
`#include "..."` lines and its duplicate `#define TRUE 1` / `FALSE 0`,
and produces the same bytes as the `sed` in
`tests/cc/build-m2planet-monolith.sh` (`verify.sh` step 5 checks the
two give the same `cc-out-v1`).  The compiler runs with its working
directory in `vendor/M2-Planet`, so `cc.h`'s own
`#include "cc_globals.h"` reads the pinned header (the `tests/`
scripts run from the repository root and pick up the identical copy
in `tests/cc/`).  `mkdir`, `rm` and `mv` only manage files; `cmp`,
`wc` and `sha256sum` only check and report.  When `unshare -rm`
works, each `seed-forth` run gets a private `/tmp`, because
`120-cc-main.fth` and `130-asm.fth` write the fixed paths
`/tmp/cc-out` and `/tmp/asm-out`.

Timings measured here (4-core x86-64, Linux 6.18): `bootstrap.sh`
28–29 s (of which the three `130-asm.fth` runs are ~20 s);
`verify.sh` 109 s.  The run's hashes, printed at the end and saved to
`$BUILDROOT/out/SHA256SUMS`:

```text
697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e  seed-forth
23aaa5be476e5d25194dcbd178ceba9a4ccc72ca9c7d76523c6fc6fc1a409e73  cc-out-v1
22465aa1b4943b830263928f79bb150bbfcbbc1642cfc287b0ed3d873a583d37  self-v1-amd64.M1
1ac93f9ba1da2369a496ac417d779be5528df0dcdd7cc9e43326115c60a08b2e  cc-out-v2
02d98f86fed9c207a8b7e1cc90429e76b282ab5c24dbbcb35e9d7bea49c888d5  self-v2-amd64.M1
e8de7c9f1cee461862f89549d27397d964b7ee629cb321c69cb7a4ed3e7d1a16  cc-out-v3
c5143ef2b56c42363935468b27e180750362d76452be0d91cb78319b38e8bfd7  M1
49781454d8708eb50f1f5748c1dae988e7f5bac14f284cc378b2966edda47643  hex2
```

`self-v1-amd64.M1` differs from `self-v2-amd64.M1` by design (the
host-arch nudge described in the `STAGE0_COMPAT` section below); the
fixed point closes at v2.

### Handing off to the next stage

`build-out/out/cc-out-v3` (or `cc-out-v2`; both compile M2-Planet to
the same `.M1`), `M1` and `hex2` are a self-hosted M2-Planet toolchain
for amd64, the toolchain the next rungs of a full-source bootstrap
consume (in stage0-posix / live-bootstrap: the rest of mescc-tools,
then GNU Mes and tcc).  This repository does not script those rungs:
what `bootstrap.sh` shows about the hand-off is the self-compile fixed
point, the `M1`/`hex2` self-rebuild and a running `hello.c`.  Link a program the way `bootstrap.sh` step 8 does: M2-Planet
`--architecture amd64` to `.M1`, then `M1` with
`M2libc/amd64/amd64_defs.M1` and `libc-full.M1`, then `hex2` with
`M2libc/amd64/ELF-amd64.hex2` at `--base-address 0x00600000`.

## Comparisons against GCC-built references

```sh
./verify.sh                    # needs gcc; ~2 min
```

`verify.sh` runs, each from scratch and in a private `/tmp` when
`unshare -rm` works: the small `tests/asm` fixtures and die gates;
`tests/cc/stage-a-check.sh`; `tests/cc/bootstrap-chain.sh` (x86 and
amd64 chains, plus M2-Planet test-suite parity); and
`tests/asm/mescc-tools-check.sh` (which runs `m2planet-check.sh`):
`130-asm.fth`'s M2-Planet, M1 and hex2 are byte-identical to what
GCC-built mescc-tools M1 + hex2 produce from the same `.M1`.  GCC
builds only the references (`m2-ref`, `M1-ref`, `hex2-ref`); nothing
it builds is assembled into, or runs as part of, the chain.

## Checks

Run from the repository root:

```sh
./build.sh
./test.sh
tests/cc/stage-a-check.sh
```

The Forth sources are fed to `seed-forth` exactly as they are in the
repository (`cat 010-lib.fth ... | ./seed-forth`): the seed's token
reader skips `\` line comments and `( ... )` comments itself, so no
text-processing tool sits between the `.fth` files and the seed.
(`tests/cc/build-m2planet-monolith.sh` still uses `sed` to drop
M2-Planet's `#include "..."` lines from the C input; that edits
M2-Planet's source, not ours.  `bootstrap.sh` does the same filtering
in bash, so `sed` is not in its trust base.)

`stage-a-check.sh` does the essential compiler compatibility check:

1. Build `seed-forth` from `000-seed.hex0`.
2. Build a GCC reference `M2-Planet` (fresh, via `tests/cc/build-gcc-refs.sh`).
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
| `000-seed.hex0` | 41,293 |
| `seed-forth` | 1,772 |
| `cc-out-v1` | 203,253 |
| `self-v1-amd64.M1` | 2,367,260 |

Hashes for the same run:

```text
16c09d3a841fb5e62b115f225361f3006075a4998f46966d83e21d991e159e8e  000-seed.hex0
697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e  seed-forth
23aaa5be476e5d25194dcbd178ceba9a4ccc72ca9c7d76523c6fc6fc1a409e73  cc-out-v1
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
etc.) must all produce the same 1772-byte binary.  Disagreement
between two assemblers on this input would be a bug in one of them.

## Stage0 cross-check and `STAGE0_COMPAT`

`tests/cc/stage0-check.sh` compares the Forth route against the
canonical stage0-posix route to M2-Planet.  It runs stage0-posix's
own AMD64 kaem chain, starting from bootstrap-seeds' `hex0-seed` and
`kaem-optional-seed`, and then does a diverse double-compile.  It uses
no host C compiler (amd64 only, about 40 s):

```sh
# once, unless `git submodule update --init --recursive` already fetched
# all of stage0-posix's nested submodules:
git -C vendor/stage0-posix submodule update --init \
    M2-Planet M2libc mescc-tools mescc-tools-extra M2-Mesoplanet
# if git.savannah.nongnu.org is unreachable, first run:
#   git -C vendor/stage0-posix config submodule.mescc-tools.url \
#       https://github.com/oriansj/mescc-tools.git

tests/cc/stage0-check.sh
```

### What stage0-posix produces

`env -i ./bootstrap-seeds/POSIX/AMD64/kaem-optional-seed` (run in a
copy at `$BUILDROOT/stage0-check/stage0-posix`) runs `kaem.amd64`.
The chain goes hex0 → kaem-0 → hex1 → hex2 → catm → M0 →
`cc_amd64` (a C compiler written in M1) → `artifact/M2` (M2-Planet
compiled by `cc_amd64`) → M1, hex2, blood-elf, kaem, … →
`AMD64/bin/M2-Planet` (Phase 15: M2-Planet compiled by
`artifact/M2`).  It then checks all 19 `AMD64/bin/*` binaries against
`amd64.answers`.  The script checks them again with the host's
`sha256sum`.  The canonical binary is `AMD64/bin/M2-Planet`, sha256
`7cf19de2…`.

### Pins: compare like with like

stage0-posix `Release_1.9.1` pins M2-Planet at `bd2fe4b0`
(Release_1.13.1) with M2libc `68a23cf`.  seed-forth pins M2-Planet at
`0a67a68` (Release_1.13.1 + 30 commits, including codegen changes)
with M2libc `eee5091`.  The Forth compiler can't compile `bd2fe4b0`
itself. That version's `grab_byte` calls `fgetc`, and the compiler's
built-in libc shims (`090-cc-emit.fth`) cover only what `0a67a68`
uses: `0a67a68` reads through `fread`. The result is
`cc: … error 93`, an undeclared identifier.  So the
check compares at `0a67a68`.  It rebuilds `vendor/M2-Planet` with
stage0's own Phase-15 recipe (`AMD64/mescc-tools-full-kaem.kaem`),
with `vendor/M2-Planet` and `vendor/M2-Planet/M2libc` in place of
stage0's `../M2-Planet` and `../M2libc`, linked by stage0's
blood-elf, M1 and hex2.  "Built by C" below means that recipe with
compiler C.

| Binary | Built by | sha256 |
|--------|----------|--------|
| `x1` | stage0 `artifact/M2` (as stage0 builds M2-Planet) | `a0271488…` |
| `z1` | stage0 `bin/M2-Planet` | `a0271488…` (= `x1`) |
| `x2` | `x1` | `6008773d…` |
| `x3` | `x2` | `6008773d…` (= `x2`, fixed point) |
| `y1` | Forth-built `cc-out-v1` (default) | `5960f76e…` |
| **`y2`** | `y1` | **`6008773d…` (= `x2`)** |
| **`y1c`** | Forth-built `cc-out-v1` with `STAGE0_COMPAT=1` | **`6008773d…` (= `x2`)** |

Self-host `.M1` output (stage-a-check.sh's input list,
`--architecture amd64 --expand-includes`):

| Compiler | self-host `.M1` sha256 | bytes |
|----------|------------------------|------:|
| default `cc-out-v1`, and GCC-built M2-Planet (`stage-a-check.sh`) | `22465aa1…` | 2,367,260 |
| `STAGE0_COMPAT=1` `cc-out-v1` | `02d98f86…` | 2,400,072 |
| `x2` (stage0 route, `0a67a68` source) | `02d98f86…` | 2,400,072 |
| `bootstrap-chain.sh` `cc-out-v2-amd64` / `v3` | `02d98f86…` | 2,400,072 |
| stage0 `bin/M2-Planet` (`bd2fe4b0` compiler, for scale only) | `56380369…` | 2,431,025 |

What is proved:

- **DDC.** Two chains have independent compiler lineages but share the
  `hex0-seed` root and stage0's M1/hex2/blood-elf. One goes stage0
  `cc_amd64` → `M2` → `x1` → `x2`; the other goes seed-forth → Forth
  C compiler → `cc-out-v1` → `y1` → `y2`. They reach the same
  M2-Planet `0a67a68` binary, byte for byte (`y2 == x2`). That result
  needs no `STAGE0_COMPAT`.
- **`STAGE0_COMPAT=1`** reaches that binary one generation early
  (`y1c == x2`). Its self-host output also equals the stage0 route's
  (`02d98f86…`).
- The default `cc-out-v1`'s self-host output differs from `x2`'s, and
  the script checks that every changed line is an add/sub-immediate
  form. The default build matches the GCC-built M2-Planet instead
  (`tests/cc/stage-a-check.sh`).

### Root cause: `&&` is bitwise in M2-Planet

The difference comes from a C-semantics mismatch inside M2-Planet's
own source, not from a stage0 or `cc_amd64` bug.
`cc_emit.c` has two guards:

```c
/* write_sub_immediate */ if((Architecture & ARCH_FAMILY_X86) && (reg == REGISTER_STACK || reg == REGISTER_ZERO))
/* write_add_immediate */ if((Architecture & ARCH_FAMILY_X86) && (reg == REGISTER_ZERO))
```

In ISO C, `&&` is logical: for `--architecture amd64` (`AMD64 = 8`,
`ARCH_FAMILY_X86 = 12`) the guard is `8 && 1` = 1. The compiler then
emits the short forms `sub_rsp,BYTE '08'` and `add_rax,BYTE '18'`.
M2-Planet compiles `&&` and `||` exactly like `&` and `|`: see
`bitwise_expr_stub` in `cc_core.c`, where `"&&"` emits
`and_rax,rbx`. The result isn't normalised to 0/1 and there is no
short circuit. `cc_amd64.M1` does the same (`logical_and` uses
`bitwise_expr_stub_string_0`, `"and_rax,rbx\n"`). So a
M2-Planet-compiled M2-Planet computes `8 & 1` = 0. It never takes the
branch and always emits the two-instruction `mov_r14, %8` /
`sub_rsp,r14` form. On `--architecture x86` the guard is `4 & 1` = 0,
with the same effect.

So the behaviour of the M2-Planet *program* depends on which kind of
compiler built it:

| M2-Planet binary built by | `&&` semantics it was compiled with | emits BYTE-immediate forms |
|---------------------------|-------------------------------------|----------------------------|
| GCC | ISO C (logical) | yes |
| seed-forth's C compiler (`cc-out-v1`) | ISO C (logical) | yes |
| `cc_amd64`, `M2`, any M2-Planet (stage0 route; our v2/v3) | M2-Planet (bitwise) | no |

This involves no uninitialised memory, undefined behaviour or
integer-width effect. It is one construct, `&&` with a non-0/1
operand. It is also the whole of the "host-arch nudge" that
`bootstrap-chain.sh` stage D reports, since v1 is ISO-built and v2 is
M2-Planet-built. `stage0-check.sh` stage 6 demonstrates it directly:
the guard, compiled by the Forth compiler, returns 1, and compiled by
M2-Planet, returns 0.

What "M2-Planet-compatible" means here:

- The Forth compiler is an ISO C (subset) compiler, not an
  M2-Planet-dialect one. Its `&&`/`||` short-circuit and yield 0/1.
  Compiling M2-Planet's source, it behaves like GCC, and `cc-out-v1`
  is byte-identical in output to GCC-built M2-Planet (Stage A).
- It is not dialect-compatible with M2-Planet on programs whose
  `&&`/`||` operands are not 0/1 or have side effects. M2-Planet's
  own source contains such a case.
- `cc-out-v1` itself *is* M2-Planet, so it emits bitwise `&&` code for
  the programs it compiles. One generation later, every route
  converges: `y2 == x2`, and the bootstrap chain's v2/v3 self-host
  output equals the stage0 route's.

`STAGE0_COMPAT=1 tests/cc/build-m2planet-monolith.sh` rewrites exactly
those two guards to `0` in the monolith before seed-forth compiles
it. This gives `cc-out-v1` the behaviour an M2-Planet-built M2-Planet
has (`cc-out-v1` shrinks from 203,253 to 203,016 bytes). With it,
`self-v1 == self-v2 == self-v3` (`02d98f86…`), and
`stage-a-check.sh` fails by design. It is a convenience for one-step
byte-identity with the stage0 route, not a correctness fix. Neither
output is wrong; both are valid M2-Planet emission. The DDC result
above holds without it.

### Verification summary

| Check | Command | Result |
|-------|---------|--------|
| Forth route vs GCC-built M2-Planet | `tests/cc/stage-a-check.sh` | `22465aa1…` == `22465aa1…` |
| stage0 chain from seeds reproduces `amd64.answers` | `tests/cc/stage0-check.sh` stage 1 | 19/19 OK |
| stage0 route fixed point at `0a67a68` | stage 3 | `x2 == x3` (`6008773d…`) |
| DDC, Forth root vs stage0 root | stage 4 | `y2 == x2` (`6008773d…`) |
| `STAGE0_COMPAT=1` shortcut | stage 5 | `y1c == x2`; self-host `02d98f86…` both |
| Root cause (`&&` semantics) | stage 6 | Forth-compiled 1, M2-Planet-compiled 0 |
| Chain v2 == v3 (default) | `tests/cc/bootstrap-chain.sh` | `02d98f86…` |

Not covered: the other stage0 architectures (x86, AArch64, RISC-V),
and a comparison against the canonical `bd2fe4b0` binary built from
its own source (no `fgetc` shim). Also not
covered is assembler independence: both routes are linked by stage0's
M1/hex2/blood-elf here.

## Full Chain

The slower closure check is:

```sh
tests/cc/bootstrap-chain.sh
```

It first runs `./bootstrap.sh` and takes `cc-out-v1`, `M1` and `hex2`
from it, so every binary in the chain below (`cc-out-v2-$ARCH`,
`cc-out-v3-$ARCH`, `hello-$ARCH-elf`) has no GCC in its provenance;
GCC builds only `m2-ref`, which is compared against and never run as
part of the chain.  (Before this, the script assembled v2 with
GCC-built `M1`/`hex2` while claiming a GCC-free v2.)  It builds:

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
