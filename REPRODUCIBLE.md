# Reproducible Bootstrap

This document records the bootstrap path from `000-seed.hex0` to a
M2-Planet-compatible compiler output.

For a reader-facing walk-through with diagrams and one paragraph per
stage, see **[Appendix C of the book](book/A3-reproducibility-chain.md)**.
This file is the operator-facing companion: exact submodule pins,
SHA-256 hashes, license notes, the cross-check against stage0-posix
(a diverse double-compile, `tests/cc/stage0-check.sh`), the hand-off
to stage0-posix's own recipe (`handoff.sh`), and the `STAGE0_COMPAT=1`
shortcut.  `STAGE0_COMPAT` is not a workaround for a stage0 quirk: the
difference it removes comes from M2-Planet's own source, which uses
`&&` in a way that means one thing in ISO C and another in M2-Planet's
dialect (see "Root cause" below).

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
`./build-out/handoff` for `handoff.sh`, and `/tmp/seed-bootstrap` for
the individual `tests/` scripts; `HEX0`
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
`handoff.sh` 75 s (17 s with `BOOTSTRAP_OUT=` and `ROUTE_B=0`, as
`check-all.sh` runs it); `tests/cc/stage0-check.sh` 41 s;
`check-all.sh` 78 s; `verify.sh` 198 s.  The run's hashes, printed at the end and saved to
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

`self-v1-amd64.M1` differs from `self-v2-amd64.M1` by design: v1 was
compiled by the Forth compiler, which evaluates M2-Planet's `&&` as
ISO C does, and v2 by v1, i.e. by M2-Planet, which compiles `&&` as a
bitwise `and` ("Root cause" below).  The fixed point closes at v2.

### Handing off to the next stage: `handoff.sh`

```sh
./handoff.sh                   # amd64 Linux; ~75 s (30 s of it bootstrap.sh)
```

stage0-posix builds its `AMD64/bin` set with three kaem scripts.
`AMD64/mescc-tools-mini-kaem.kaem` Phases 1–5 go hex0 → hex1 →
hex2-0 → catm → M0 → `cc_amd64` → `artifact/M2` (M2-Planet `bd2fe4b`
compiled by `cc_amd64`); Phases 6–11 use `M2` to build blood-elf-0,
M1-0, hex2-1, `bin/M1`, `bin/hex2` and `bin/kaem`; `AMD64/kaem.run`
then builds M2-Mesoplanet, blood-elf, get_machine, M2-Planet and
mescc-tools-extra and checks all 19 binaries against
`amd64.answers`.  `handoff.sh` replaces Phases 0–5 with the Forth
route and runs the rest of that recipe unchanged:

| Stage | What runs | Result (this machine) |
|-------|-----------|-----------------------|
| 1 | `bootstrap.sh` (or `BOOTSTRAP_OUT=` a verified earlier output) | `cc-out-v2`, `cc-out-v3`, `M1`, `hex2` |
| 2, route A | stand-ins: `artifact/catm` = `mescc-tools-extra/catm.c` compiled by v3; `artifact/M0` and `artifact/hex2-0` = two-line bash scripts calling the Forth-route `M1` and `hex2`; `artifact/M2` = Phase 5's own input `M2-0.c` (M2-Planet `bd2fe4b` + M2libc's `bootstrap.c`) compiled by v3 in `--bootstrap-mode` and linked with M2libc's `amd64_defs.M1`/`libc-core.M1`/`ELF-amd64.hex2`.  Then Phases 6–11 (run by bash, from the Phase-6 banner on) and `kaem.run` (run by the `bin/kaem` Phase 11 built), under `env -i` | `artifact/M2` `bfd5f5e9…` (198,456 bytes); **19/19 match `amd64.answers`** (the recipe's own `sha256sum -c`, then the host's); `bin/M2-Planet` = `7cf19de2…` |
| 3, route B | the plainest substitution: `artifact/M2` = `cc-out-v2` as is (M2-Planet `0a67a68`) | 12/19 match.  The 7 that `artifact/M2` compiles itself differ (blood-elf, get_machine, hex2, kaem, M1, M2-Mesoplanet, M2-Planet): `0a67a68` generates different code from `bd2fe4b`.  The 12 built through the recipe's `bin/M2-Planet` (`bd2fe4b` source) already match.  `bin/M2-Planet` = `7ba96276…` |
| 3b | one generation later: `artifact/M2` = route B's `bin/M2-Planet` | **19/19 match**, each byte-identical to route A's |
| 4 (optional) | `LIVE_BOOTSTRAP=<checkout>`: what live-bootstrap's `seed/seed.kaem` does first, i.e. `M2-Mesoplanet` on `seed/configurator.c` and `seed/script-generator.c`, then `sha256sum -c` against its `*.amd64.checksums` | both OK with route A's tools (live-bootstrap `b1ceced`, which pins stage0-posix at the same `45d90f5`) |

So the answer to "can the M2-Planet the Forth route builds (`0a67a68`)
drive stage0's recipe for `bd2fe4b`?" is: not in one step (route B,
7 of 19 differ), and yes one generation later (route B's
`bin/M2-Planet` in the `artifact/M2` slot gives all 19), or directly
if v3 compiles stage0's own Phase-5 input (route A).

What route A runs: of stage0-posix's seed binaries only the 229-byte
`hex0-seed` (through `bootstrap.sh`); `bootstrap-seeds` is not even
copied into the work tree, so `kaem-optional-seed` never runs, and
none of hex0, kaem-0, hex1, hex2-0, catm, M0, `cc_amd64` or stage0's
own `M2` is built.  Every other binary that runs is either a Forth
route output or built by the recipe from stage0-posix's sources.  What it trusts besides
`bootstrap.sh`'s base: the stage0-posix *sources* at its pins (kaem
scripts, M2libc, M2-Planet `bd2fe4b`, mescc-tools `5adfbf3`,
mescc-tools-extra, M2-Mesoplanet), and the host `bash` running
Phases 6–11 where stage0 uses its `kaem-0`.  The script's header
lists it exactly.

Where live-bootstrap takes over.  live-bootstrap (read at `b1ceced`)
vendors stage0-posix as `seed/stage0-posix` at `45d90f5`, the same
pin as `vendor/stage0-posix`, and starts it by running
`kaem-optional-seed`, which reads `kaem.amd64`.  It hooks in at stage0-posix's
last line, `exec ./AMD64/bin/kaem --verbose --strict --file
./after.kaem`: its own `seed/after.kaem` runs `seed/seed.kaem`, which
copies the 19 `amd64.answers` binaries out of `/AMD64/bin`, sets
`M2LIBC_PATH=/M2libc`, builds and checksums `configurator` and
`script-generator` with `M2-Mesoplanet`, and hands on to `/steps`
(Mes, MesCC, TinyCC, …).  Since route A's `AMD64/bin` is
byte-identical to stage0-posix's, everything from `after.kaem` on
sees exactly the files it expects: **continue with live-bootstrap as
usual from that hook.**  What a bootstrapper does by hand: put route
A's `AMD64/bin` (with stage0-posix's `M2libc`) where live-bootstrap's
target expects `/AMD64/bin` and start at `after.kaem` instead of at
`kaem.amd64`; `handoff.sh` does not modify or drive live-bootstrap,
and runs only its first step (stage 4).  Caveats: live-bootstrap's
default and only supported architecture is x86 (its `rootfs.py` says
the others "are for development only"), and the Forth route is
amd64 only, so this hand-off is to live-bootstrap's amd64 path.

`bootstrap.sh`'s own `M2-Planet` binaries remain usable on their own:
link a program the way `bootstrap.sh` step 8 does (M2-Planet
`--architecture amd64` to `.M1`, then `M1` with
`M2libc/amd64/amd64_defs.M1` and `libc-full.M1`, then `hex2` with
`M2libc/amd64/ELF-amd64.hex2` at `--base-address 0x00600000`).

## Comparisons against GCC-built references

```sh
./verify.sh                    # needs gcc; ~3½ min
```

`verify.sh` runs, each from scratch and in a private `/tmp` when
`unshare -rm` works: the small `tests/asm` fixtures and die gates;
`tests/cc/stage-a-check.sh`; `tests/cc/bootstrap-chain.sh` (x86 and
amd64 chains, plus M2-Planet test-suite parity); and
`tests/asm/mescc-tools-check.sh` (which runs `m2planet-check.sh`):
`130-asm.fth`'s M2-Planet, M1 and hex2 are byte-identical to what
GCC-built mescc-tools M1 + hex2 produce from the same `.M1`.  GCC
builds only the references (`m2-ref`, `M1-ref`, `hex2-ref`); nothing
it builds is assembled into, or runs as part of, the chain.  Then,
without gcc, `tests/cc/stage0-check.sh` and the full `./handoff.sh`
(on step 3's `bootstrap.sh` output); each prints SKIP (exit 77)
instead of failing when stage0-posix's nested submodules are not
checked out.

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
operand. It is also the whole of the v1-versus-v2 self-compile
difference that `bootstrap-chain.sh` stage D reports (and
`bootstrap.sh` step 6 notes), since v1 is ISO-built and v2 is
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
| Forth route drives stage0's recipe from Phase 6 | `./handoff.sh` stage 2 | 19/19 `amd64.answers` |
| `cc-out-v2` as `artifact/M2`, then one generation later | `./handoff.sh` stage 3 | 12/19, then 19/19 |

Not covered by `stage0-check.sh`: the other stage0 architectures (x86,
AArch64, RISC-V), and a Forth-compiled `bd2fe4b0` (no `fgetc` shim).
It does not show assembler independence either: both routes are
linked by stage0's M1/hex2/blood-elf there.  `handoff.sh` covers part
of that gap from the other side: in its route A nothing from
stage0's hex/M0/`cc_amd64` phases runs, the Forth route's own `M1`
and `hex2` link the first tools, and the canonical `bd2fe4b0` binary (`7cf19de2…`) and the
other 18 come out byte for byte.

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
