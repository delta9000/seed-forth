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
| pnut | `vendor/pnut` | `abc34a5` (`abc34a5207b1373d0a4e3dcb3d3d6df6e22ae23d`) | — |

The amd64 route to TinyCC also uses tcc-0.9.27.  Its source is the tarball
vendored inside pnut, `kit/tcc-0.9.27.tar.gz`, with sha256
`db0a0bf390c746621b2dc9b8ddf9ff4eeda0c7e3e65e292de5bd8be902eb230d`.
`tests/pnut/sf-pnut-amd64-check.sh` checks that hash before it uses the
tarball.  The route's own patches to pnut, tcc and pnut's libc are in
`patches/amd64/`.  See "Past M2-Planet on amd64 alone" below.

The amd64 chain on to GCC 15.2 (`gcc64/run-gcc64.sh`) uses eleven more
source tarballs (musl, binutils, flex, gmp, mpfr, mpc, four GCCs).  They
are not vendored or submodules: `gcc64/SOURCES` pins each by sha256 with
its URLs, and the script fetches them into a gitignored cache and
refuses any mismatch.  See "Past TinyCC on amd64: GCC 15.2 via musl"
below.

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
`handoff.sh` 75 s with `ARCHES=amd64` (17 s with `BOOTSTRAP_OUT=` and
`ROUTE_B=0` too, as `check-all.sh` runs it), 245–272 s with the default
`ARCHES="amd64 x86"` (196–215 s of it stage0's x86 recipe);
`tests/cc/stage0-check.sh` 44–56 s with `BOOTSTRAP_OUT=`;
`check-all.sh` 78 s; `verify.sh` 394 s.  The run's hashes, printed at the end and saved to
`$BUILDROOT/out/SHA256SUMS`:

```text
697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e  seed-forth
025208db31342c4070dbcd3b72f56ddfdde7d38c582c96ea9fdc59bcc6ef7d1e  cc-out-v1
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
./handoff.sh                   # amd64 Linux; amd64 + x86, ~4½ min (see below)
ARCHES=amd64 ./handoff.sh      # amd64 only, ~75 s (30 s of it bootstrap.sh)
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
| 2, route A for x86 | the same stand-ins, made by the same amd64 Forth-route tools with `--architecture x86`: `artifact/catm` and `artifact/M2` are i386 ELFs (`M2-0.c` with M2libc's `x86/linux/bootstrap.c`, linked with M2libc's `x86_defs.M1`/`libc-core.M1`/`ELF-x86.hex2` at `0x08048000`); `M0`/`hex2-0` call `M1`/`hex2 --architecture x86`.  Then stage0-posix's `x86/mescc-tools-mini-kaem.kaem` from Phase 6 and `x86/kaem.run`, unchanged | `artifact/M2` `e96ac431…` (159,936 bytes); **19/19 match `x86.answers`**; `x86/bin/M2-Planet` = `f4267292…` |
| 4 (optional) | `LIVE_BOOTSTRAP=<checkout>`: what live-bootstrap's `seed/seed.kaem` does first, i.e. `M2-Mesoplanet` on `seed/configurator.c` and `seed/script-generator.c`, then `sha256sum -c` against its `*.<arch>.checksums`, for each arch route A passed | amd64: both OK with route A's tools (live-bootstrap `b1ceced`, which pins stage0-posix at the same `45d90f5`) |

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
the others "are for development only").  Route A for x86 (next
subsection) gives the byte-identical `x86/bin` set, so the same hook
works on live-bootstrap's supported path, as long as the machine that
runs the Forth route also runs amd64 binaries.

### The x86 (i386) hand-off

`ARCHES` (default `amd64 x86`) selects the architectures.  For x86,
`handoff.sh` builds every stand-in with the amd64 Forth-route tools
cross-targeting i386: v3 is M2-Planet and takes `--architecture x86`,
and `M1`/`hex2` take `--architecture x86`.  stage0-posix's
`x86/mescc-tools-mini-kaem.kaem` then runs from Phase 6 (the Phase-6
banner on) and `x86/kaem.run` runs with the `x86/bin/kaem` it built.
Everything from Phase 6 on is an i386 ELF, so the kernel must run
32-bit binaries: an x86-64 kernel with IA-32 emulation
(`CONFIG_IA32_EMULATION`, on in stock distribution kernels; this VM's
6.18 kernel has it).  Stage 2 runs the Forth-built i386 `catm` once
first; if the kernel cannot run it, or `vendor/stage0-posix/x86` is not
checked out, x86 is skipped and the script exits 77 after amd64 has
passed.  Result: **all 19 `x86.answers` binaries byte for byte**
(`SHA256SUMS.x86`), `x86/bin/M2-Planet` = `f42672922b50bff8…`.

Timing: stage0's x86 recipe took 196–215 s on this VM, against 16 s for
AMD64, almost all of it kernel time spent in the i386 binaries'
system calls.  stage0-posix's own x86 chain from its seeds took 300 s
(265 s system time) on the same VM, so the cost is the recipe on this
kernel, not the hand-off.  `check-all.sh` therefore runs
`ARCHES=amd64 ROUTE_B=0`; `verify.sh` runs everything.

What x86 still needs: an amd64 kernel.  The x86 route has no x86 seed;
the 1,772-byte seed-forth is an x86-64 ELF, and the Forth compiler
and assembler run inside it.  That helps a bootstrapper whose kernel
runs both (the common case on x86-64 hardware), not a pure-i386
machine.  A 32-bit port would need a new seed: an ELF32 header and
program header, the 32 primitives re-encoded without REX prefixes
and with 32-bit registers, `int 0x80` with the i386 system-call
numbers and argument registers in place of `syscall`, and 4-byte
cells, so every hand-computed offset in `000-seed.hex0` changes.
`010-lib.fth` would need the i386 system-call numbers and a 4-byte
cell size; the C compiler would need an i386 back end
(`080-cc-elf.fth` writes ELF64, `090-cc-emit.fth` and
`100-cc-expr.fth` emit x86-64 bytes), so that `cc-out-v1` is an i386
program.  From M2-Planet on, nothing changes: its x86 output is
already what `handoff.sh` feeds stage0's x86 recipe.  None of this is
done here.

`bootstrap.sh`'s own `M2-Planet` binaries remain usable on their own:
link a program the way `bootstrap.sh` step 8 does (M2-Planet
`--architecture amd64` to `.M1`, then `M1` with
`M2libc/amd64/amd64_defs.M1` and `libc-full.M1`, then `hex2` with
`M2libc/amd64/ELF-amd64.hex2` at `--base-address 0x00600000`).

## Comparisons against GCC-built references

```sh
./verify.sh                    # needs gcc; ~6½ min
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
(both on step 3's `bootstrap.sh` output; `handoff.sh` for amd64 and
x86); each prints SKIP (exit 77) instead of failing when
stage0-posix's nested submodules are not checked out (`handoff.sh`
also when x86 cannot run: no `vendor/stage0-posix/x86` or no IA-32
emulation).

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
| `cc-out-v1` | 202,405 |
| `self-v1-amd64.M1` | 2,367,260 |

Hashes for the same run:

```text
16c09d3a841fb5e62b115f225361f3006075a4998f46966d83e21d991e159e8e  000-seed.hex0
697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e  seed-forth
025208db31342c4070dbcd3b72f56ddfdde7d38c582c96ea9fdc59bcc6ef7d1e  cc-out-v1
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
`kaem-optional-seed`, and then does a diverse double-compile, first
with shared linkers and then (stage 4b) with each route linking only
with its own tools.  It uses no host C compiler (amd64 only, about
60 s including a `bootstrap.sh` run; `BOOTSTRAP_OUT=<a verified
bootstrap.sh output>` skips that run):

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

Stage 4b repeats the DDC with fully separate tool lineages.  The
stage0 side is `x1`/`x2` above: compiled, footed and linked only by
stage0's chain.  The Forth side uses only Forth-route binaries:
`bootstrap.sh`'s `cc-out-v1` and `cc-out-v3`, its `M1` and `hex2`
(compiled by our M2-Planet, first assembled by `130-asm.fth`), and a
`blood-elf` that `cc-out-v3` compiles from `vendor/mescc-tools` and
that `M1`/`hex2` link (`ab6bb1c3…`).  No stage0 binary touches it.

| Binary | Compiler | Linked by | sha256 |
|--------|----------|-----------|--------|
| `f1` | `bootstrap.sh`'s `cc-out-v1` | Forth-route tools | `5960f76e…` (= `y1`: the two linker lineages agree) |
| **`f2`** | `f1` | Forth-route tools | **`6008773d8e59562d…` (= `x2`)** |
| M1 | `f2` / `x2`, mescc-tools `5adfbf3` source | each route's own | `bb1dd0284c4627dd…` both |
| hex2 | same | each route's own | `2169f45627d1e72b…` both |
| blood-elf | same | each route's own | `6588e3c4a760d842…` both |

What is independent in stage 4b: every *binary* that runs, from the
seed on (stage0: hex0 → kaem-0 → hex1 → hex2 → catm → M0 →
`cc_amd64` → M2 → its M1/hex2/blood-elf; ours: seed-forth → Forth C
compiler → M2-Planet → `130-asm.fth` → M1/hex2 → blood-elf).  What is
still shared: the 229-byte `hex0-seed` *file* (stage0 runs it on
`hex0_AMD64.hex0`, we run it on `000-seed.hex0`); the *sources* both
sides compile or assemble, namely M2-Planet `0a67a68`, the
M1/hex2/blood-elf sources (stage0-posix's mescc-tools `5adfbf3`;
`vendor/mescc-tools` `9b13751` has the same files), and
`vendor/M2-Planet`'s M2libc, whose `amd64_defs.M1`, `libc-full.M1`
and ELF headers both linkers read; the Linux kernel; and bash.  A
compromised binary on one side would have to reproduce the other
side's output from these sources to go unnoticed.

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

- **DDC.** Two chains have independent compiler lineages. Stage 4 has
  them share stage0's M1/hex2/blood-elf; stage 4b gives each its own
  (above). One goes stage0
  `cc_amd64` → `M2` → `x1` → `x2`; the other goes seed-forth → Forth
  C compiler → `cc-out-v1` → `y1` → `y2`. They reach the same
  M2-Planet `0a67a68` binary, byte for byte (`y2 == x2`, and with
  separate linkers `f2 == x2`), and rebuild byte-identical M1, hex2
  and blood-elf. That result needs no `STAGE0_COMPAT`.
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
has (`cc-out-v1` shrinks from 202,405 to 202,168 bytes). With it,
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
| DDC, each route linked only by its own M1/hex2/blood-elf | stage 4b | `f2 == x2` (`6008773d…`); M1, hex2, blood-elf rebuilt identical |
| `STAGE0_COMPAT=1` shortcut | stage 5 | `y1c == x2`; self-host `02d98f86…` both |
| Root cause (`&&` semantics) | stage 6 | Forth-compiled 1, M2-Planet-compiled 0 |
| Chain v2 == v3 (default) | `tests/cc/bootstrap-chain.sh` | `02d98f86…` |
| Forth route drives stage0's recipe from Phase 6 | `./handoff.sh` stage 2 | 19/19 `amd64.answers` |
| `cc-out-v2` as `artifact/M2`, then one generation later | `./handoff.sh` stage 3 | 12/19, then 19/19 |
| Forth route drives stage0's x86 recipe from Phase 6 | `./handoff.sh` stage 2 (x86) | 19/19 `x86.answers` |

Not covered by `stage0-check.sh`: the other stage0 architectures (x86,
AArch64, RISC-V), and a Forth-compiled `bd2fe4b0` (no `fgetc` shim).
`handoff.sh` covers x86 from the other side: its route A, on AMD64
and on x86, runs nothing from stage0's hex/M0/`cc_*` phases, the
Forth route's own `M1` and `hex2` link the first tools, and all 19
binaries of each arch, among them the canonical `bd2fe4b0` M2-Planet
(`7cf19de2…` amd64, `f4267292…` x86), come out byte for byte.

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

## Past M2-Planet: pnut and TinyCC

`tests/pnut/sf-pnut-check.sh` takes the chain in a second direction,
past M2-Planet to TinyCC, with no Mes and no GCC:

```sh
tests/pnut/sf-pnut-check.sh                   # stages 1-2, ~15 s
SF_PNUT_TCC=1 tests/pnut/sf-pnut-check.sh     # and stage 3, ~2 min
```

1. The Forth C compiler (`010-lib.fth` + `[0-9][0-9][0-9]-cc-*.fth`)
   compiles `vendor/pnut/pnut.c` exactly as shipped.  It reads stdin,
   so the configuration, pnut's own `compile-with-M2-Planet` CI flags
   `target_i386_linux NO_TERNARY_SUPPORT ONE_PASS_GENERATOR
   SMALL_HEAP`, goes in front as `#define NAME 1` lines, the
   equivalent of `-D`.  The result, `sf-pnut`, is an amd64 program that
   generates i386 code.
2. `bootstrap.sh`'s `cc-out-v3`, `M1` and `hex2` build an M2-Planet
   pnut from the same source and flags (`m2-pnut`, i386).  Both compile
   `pnut.c` with the TinyCC kit's options (`-Dtarget_i386_linux
   -DONE_PASS_GENERATOR -DSUPPORT_EMULATED_INT64
   -DUNDEFINED_LABELS_ARE_RUNTIME_ERRORS -DENABLE_PNUT_INLINE_INTERRUPT
   -DNO_BUILTIN_LIBC`), and the two `pnut-exe` must be byte-identical:
   sha256 `19d96d9ed04eacaab4bba58cc3a8fcf180ac4ec88369599ef3c20d349d0fb159`.
   (Without the kernel's IA-32 emulation `m2-pnut` cannot run, and
   `sf-pnut`'s output is compared with that hash instead.)
3. pnut's own `kit/bootstrap.sh` carries that `pnut-exe` on through its
   `bintools`, tcc-0.9.27 with the kit's patches, and pnut's portable
   libc to `tcc-boot0` … `tcc-boot3`.  `tcc-boot2` and `tcc-boot3` must
   both be `03e96a1a63cc9bb3f577a14e50d20476507e3759bdc803f79e31d184bba44185`,
   the hash pnut's kit README publishes.

`check-all.sh` runs stages 1-2 (step 06a); `verify.sh` runs all three
(step 8).  The one trusted input added is pnut's source tree
(`pnut.c`, `x86.c`, `exe.c`, `elf.c`, and for stage 3 the kit, its
tcc-0.9.27 tarball and patches, and `portable_libc`).

## Past M2-Planet on amd64 alone

`tests/pnut/sf-pnut-amd64-check.sh` climbs to TinyCC with every program
an x86-64 ELF.  No IA-32 emulation is needed, and no gcc runs:

```sh
tests/pnut/sf-pnut-amd64-check.sh                          # ~10 s; check-all.sh step 06b
SF_PNUT64_GCC_ORACLE=1 tests/pnut/sf-pnut-amd64-check.sh   # + gcc reference, ~16 s; verify.sh step 9
```

Output goes to `./build-out/pnut-amd64` (`BUILDROOT=`), which is wiped at
the start of each run.  When `unshare -rm` works, the script runs with a
private `/tmp`.

### Pins

| Input | Pin |
|---|---|
| pnut (`vendor/pnut`) | commit `abc34a5207b1373d0a4e3dcb3d3d6df6e22ae23d` (the script fails on any other `HEAD`) |
| tcc-0.9.27 source | `vendor/pnut/kit/tcc-0.9.27.tar.gz`, sha256 `db0a0bf390c746621b2dc9b8ddf9ff4eeda0c7e3e65e292de5bd8be902eb230d` (added to pnut by commit `920cb3f`; the tcc 0.9.27 release tree of 2017-12-17; checked before bintools unpacks it) |
| `tcc-0.9.27/lib/va_list.c` (goes into `libtcc1.a` unmodified) | sha256 `3204e28b30bc7cbd4ea9520377e69a6feef11e110081bd05d1136fdcbf50c6f1` (checked after unpacking) |
| the kit's 8 tcc patches, `kit/config.h`, `kit/libtcc1.c`, `kit/bintools/`, `portable_libc/` | pnut commit above |
| our patches | `patches/amd64/{pnut,tcc,libc}/*.diff`, in this repository |

The upstream tcc project distributes 0.9.27 as `tcc-0.9.27.tar.bz2`
(download.savannah.gnu.org/releases/tinycc/).  No script compares pnut's
`.tar.gz` with that file.

### Stages and hashes

| Stage | Artifact | sha256 | Bytes | Time |
|---|---|---|---:|---:|
| 1 | SF compiles `pnut.c` (as shipped; `#define target_x86_64_linux 1`, `#define ONE_PASS_GENERATOR 1`) → `sf-pnut64` | `e05b69f8d5eb010507bd87fde3ef185417da4f1ed73df78a1e8dc26dbc3bfeb8` | 152,480 | 1.9 s |
| 2 | `sf-pnut64` → `pnut64-g2` → `pnut64-g3`, g2 = g3 | `5bee065d3332230129036b1e7b154ef2ed8bc2fee643135f227e1c39f856f0de` | 230,706 | 0.5 s |
| 3 | `sf-pnut64 pnut.c` with the kit options for x86_64 → `pnut-exe` | `b9ebaecc589e9944f25827df112257a2ff1ed0eb9df1c50cb21cd79b21b1d1a1` | 230,454 | 0.6 s |
| 3 | `pnut-exe` → `bintools` | `6aafe3ce91ae38772c607f9b75709046a16bb0df1cd134c6f57ecb6ded156205` | 87,162 | <0.1 s |
| 4 | unpack and patch tcc-0.9.27 (8 kit + 4 amd64 patches); `libc64` = portable_libc + 6 patches | — | | 1.6 s |
| 5 | `pnut-exe` builds `pnut.c` + `01-heap-size.diff`, without ONE_PASS_GENERATOR, with SAFE_MODE and libc64 → `pnut-exe-for-tcc` | `b8ade68772e2d360e28109e9ea2d0a91c5091332a269deee0c363e69e77bad53` | 279,456 | 0.4 s |
| 6 | `pnut-exe-for-tcc` compiles `tcc.c` (`TCC_TARGET_X86_64`) → `tcc-pnut` | `97d00391969ea15eb35707d57e14b9f0576bfdfc22d807b6ba568e2fc543b5e4` | 1,120,921 | 2.1 s |
| 6 | `tcc-boot0` | `0605483829e454c0a0422c28949ecec94d9b3624d294a9f65d8f16b7923b15de` | 305,496 | 0.9 s |
| 6 | `tcc-boot1` | `c382b52cc298438c52d6626e9a535b17d1177d0f93e1899bd8d681c58878a886` | 305,496 | 0.6 s |
| 6 | `tcc-boot2` = `tcc-boot3` (and `tcc-boot2.o` = `tcc-boot3.o`) | `514bc4d3af6b79d2fc99d1178933f3e2ee093ff7ce7362d92dc81708f13fa5c1` | 305,496 | 1.2 s |
| 6 | `boot2-lib/crt1.o` | `9fc015dbe5674217d8d2b92b0bdbed91f3456b2b80afeb72c27a16ffa0247d51` | 2,016 | |
| 6 | `boot2-lib/libc.a` | `6f35761d40d06c58b1e3a014110b0b59a4dd6db1a140769ddf4474d524d7c86a` | 22,384 | |
| 6 | `boot2-lib/tcc/libtcc1.a` | `21312cd01450bba923f9c1f91193b810693084a5bf98bcc51d2ddce78057307e` | 3,170 | |
| 7 | functional tests (below) | — | | 0.4 s |

The kit options in stage 3 are `-Dtarget_x86_64_linux -DONE_PASS_GENERATOR
-DUNDEFINED_LABELS_ARE_RUNTIME_ERRORS -DENABLE_PNUT_INLINE_INTERRUPT
-DNO_BUILTIN_LIBC`.  They are kit/bootstrap.sh's `PNUT_EXE_TCC_OPTIONS`
without the i386-only `SUPPORT_EMULATED_INT64`.  Stage 6's `go` is
kit/bootstrap.sh's `go()` with `TCC_TARGET_X86_64`, libc64 as the libc,
and `lib/va_list.c` added to `libtcc1.a`.  The timings come from one run
on the development machine: 10.2 s wall-clock in total, and 15.6 s with
the gcc reference.

Stage 5 drops ONE_PASS_GENERATOR because that mode caps output at
1,000,000 bytes, and `tcc-pnut` is 1.12 MB.  With `SF_PNUT64_REPIN=1`
the script prints the stage hashes instead of failing on them.  Use it
after a deliberate patch change.

### Patches (`patches/amd64/`, README there)

| Patch | Why |
|---|---|
| `pnut/01-heap-size.diff` | `HEAP_SIZE` 786,432 → 1,048,576 words.  x86_64 tcc needs 790,991, and pnut has no `-D` override.  Applied to a copy used only for `pnut-exe-for-tcc`. |
| `tcc/01-local_enum.diff` | pnut rejects a block-scope `enum`.  Uses `#define`s under `PNUT_CC`. |
| `tcc/02-vla_onstack.diff` | pnut has no VLAs.  Uses a fixed 512-byte array under `PNUT_CC`. |
| `tcc/03-static_no_plt.diff` | tcc-0.9.27 bug: an x86_64 `-static` exe calls through a PLT that `relocate_plt` never fills (it runs only when there is a `.dynamic` section). |
| `tcc/04-static_fill_got.diff` | tcc-0.9.27 bug: `fill_got` runs after `tidy_section_headers` has moved the `.rela` sections out of its range, so the GOT stays zero. |
| `libc/01-crt1-x86_64.diff` | x86_64 `_start` and `syscall` wrappers (portable_libc has only i386). |
| `libc/02-stdarg-x86_64.diff` | tcc's x86_64 `va_list` under `__TINYC__ && __x86_64__`. |
| `libc/03-assert-h.diff`, `libc/04-abort.diff` | `<assert.h>` and `abort()`, which `x86_64-gen.c` uses. |
| `libc/05-puts-newline.diff` | `puts` appends `'\n'`. |
| `libc/06-printf-length.diff` | `printf` handles `l`/`ll` (`%ld %lld %lu %llu %lx …`), and `%u`/`%o`/`%x` are unsigned. |

Evidence that 03 and 04 are tcc's bugs and not pnut's: a gcc-built
tcc-0.9.27, with the same sources and flags and without them, builds a
static hello-world that segfaults.  That binary is byte-identical to the
one the pnut-built tcc makes (sha256 `e3c6d1b2…`).  With either patch
alone the result still crashes.  This was established once, by hand, and
is not rerun by a script.  i386 does not need these two patches.

### Functional tests (stage 7)

`tcc-boot2` compiles each of the following, statically, and each binary's
output must match exactly:

- `tests/pnut/amd64/t64.c`: 64-bit multiply, divide and modulo; signed and
  unsigned shifts; sign and zero extension; `sizeof(long) == 8`; struct
  layout; recursion; malloc.
- `hello.c`: exit status 7, and `%lld`/`%ld` of `1 << 40`.
- `printf.c`: length modifiers, unsigned conversions, widths and flags,
  `LLONG_MIN`, `ULLONG_MAX`, and `puts`.  This test fails 15 checks
  against unpatched portable_libc.
- portable_libc's own `test-libc.c`: all 136 checks pass.

`pnut-exe` also builds `printf.c` with libc64, which is pnut's side of
the same libc.  The `long` cases are left out there, because pnut's
`long` is 4 bytes.  Finally, `tcc-boot2` compiles `pnut.c`, and that pnut
rebuilds `pnut64-g2` byte for byte.

### Reference comparison (verify.sh step 9, `SF_PNUT64_GCC_ORACLE=1`)

This runs after the GCC-free chain and takes no part in it:

- A gcc-built pnut, with stage 1's flags, builds the same `pnut64-g2`
  and `pnut-exe` as `sf-pnut64`.
- A gcc-built `tcc.c` (the same patched tree, tcc-pnut's `-D` flags, host
  libc) seeds its own boot0 → boot1 → boot2.  That `tcc-boot2`, and its
  boot2 `crt1.o`, `libc.a` and `libtcc1.a`, are byte-identical to the
  pnut-seeded ones.

This route trusts two things beyond the i386 route: the patches in
`patches/amd64/`, and GNU `patch`, which applies them.  The tcc tarball is
the same one the i386 route's stage 3 unpacks.  Here its hash is checked.

## Past TinyCC on amd64: GCC 15.2 via musl

`gcc64/run-gcc64.sh` carries the amd64 route on from `tcc-boot2` to
GCC 15.2.0 with no host compiler, assembler or linker (a guard refuses
them, on `PATH` and by absolute path).  `gcc64/README.md` has the
chain, the per-stage table, the trust statement and the open issues;
`patches/gcc64/README.md` has every patch.  It takes about 100 minutes
on 4 cores, so it is not in `check-all.sh`; `verify.sh` runs it as step
10 only with `VERIFY_GCC64=1` (SKIP otherwise), starting from step 9's
`tcc-boot2` (`GCC64_STAGE0`, checked against `sf-pnut-amd64-check.sh`'s
pins).

```sh
gcc64/run-gcc64.sh --fetch          # sources into build-out/gcc64-cache (GCC64_CACHE)
gcc64/run-gcc64.sh                  # stages 0-12 + pins, in build-out/gcc64 (BUILDROOT)
BUILDROOT=DIR gcc64/run-gcc64.sh stage11 stage12   # re-run stages in place
```

### Pins

- **Sources:** `gcc64/SOURCES`, one line per tarball: name, sha256, URLs
  (upstream first, then the Ubuntu archive URL actually used).  Eight
  of the eleven are byte-identical to live-bootstrap `b1ceced7`'s pins;
  gmp is Debian's `+dfsg` repack, gcc-4.7.4 an `.xz` (lb pins the
  `.bz2`; the uncompressed tar's hash is recorded for comparison), and
  gcc-4.0.4 a `git archive` of gcc-mirror's `releases/gcc-4.0.4` tag
  (commit `944765863eec87a9f37e297994fd2af960397138`), pinned as the
  uncompressed tar, sha256
  `091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67`,
  which a fresh clone and `git archive` reproduced.  Every file is
  checked before any stage runs; a mismatch fails, and a source that is
  neither cached nor fetchable is a SKIP (exit 77).
- **tcc-0.9.27 and portable_libc:** via stage 0, pinned as in the
  previous section.
- **Patches:** `patches/gcc64/`; those from live-bootstrap are
  byte-identical to its files below a three-line provenance header.
- **Artifacts:** `gcc64/HASHES`, checked by the pins step at the end of
  every run.

### Fixed points (enforced wherever it runs)

| Stage | Fixed point |
|---|---|
| 0 | `pnut64-g2 = g3`; `tcc-boot2 = tcc-boot3` (`514bc4d3…`) |
| 2 | musl-2 = musl-3 (`libc.a` `57d4b5e9…`); tcc-2 = tcc-3 |
| 6 | gcc-B = gcc-C in `bin/gcc`, `bin/cpp`, `cc1`, `collect2`, `libgcc.a`, `crtbegin.o`, `crtend.o` |
| 11 | gcc-15.2.0's `make compare`: "Comparison successful" (stage2 = stage3) |

### Path dependence

Most outputs embed absolute paths under `BUILDROOT` (install prefixes,
sysroot, tcc's library paths, flex's `m4`, source paths), so their
hashes hold only at the build path.  A second build of stages 0–7 in
another directory (with `JOBS=2`) gave the same bytes for `tcc-boot2`,
musl's `libc.a` (built by tcc and by gcc-B), `libgmp.a` and gcc-B's
`crtbegin.o`/`crtend.o`, and different bytes for everything else
(every tcc after `tcc-boot2`, `libtcc1.a`, binutils, flex, gcc-4.0.4,
`libgcc.a`, `libmpfr.a`, `libmpc.a`).  `HASHES` marks the former `any`
(enforced for every `BUILDROOT`) and the rest `root` (enforced only at
the canonical `BUILDROOT`, the development sandbox's
`/tmp/claude-0/-home-user-seed-forth/cc676fea-56ac-5a23-8fc7-209074f2e383/scratchpad/gcc64/clean`).

At that path two independent from-scratch runs, the development kit's
and the repository scripts' on 2026-09-27, produced all 43 pinned
artifacts bit for bit.

### Canonical hashes (`BUILDROOT` as above)

| Artifact | Built by | sha256 |
|---|---|---|
| `tccboot/kit/build/tcc-boot2` (any path) | tcc-boot1 | `514bc4d3af6b79d2fc99d1178933f3e2ee093ff7ce7362d92dc81708f13fa5c1` |
| `p0/bin/tcc` (tcc-p0) | tcc-boot2 | `58a727bf581d451c9b958beed99ba3267f898779e29078af4dc8d833d8014440` |
| `m1/lib/libc.a` (musl-1, any path) | tcc-p0 | `4cccfbd5e2eb803abcbbd6b4bc118e9028127220cdc6d78f6b91b39a6afe8ac6` |
| `tc/lib/libc.a` (musl-2 = musl-3, any path) | tcc-1, tcc-2 | `57d4b5e9f78026c4ea9f05ed32b3cc27f955c9f56e167727c69aa4343e5c74ac` |
| `tc/bin/tcc` (tcc-2 = tcc-3) | tcc-1, tcc-2 | `c716b5cbfb7048c2fc6c3947bb8af53334a97d79f772c8704e542f8e5281aad9` |
| `bu/bin/as` (binutils-2.30) | tcc | `2e84e27648fb6610075400d39987376fc43827e1b36d047172199dc55e47ff52` |
| `bu/bin/ld` | tcc | `09fac7ff68ce65ba24efd5a4ad508e56bbc92c7a67734bf96c5790b9af3c0a8c` |
| `tools/bin/flex` | tcc | `0e4154018e502a194977022fc34ecdd5892a95b055fa34344bb3afdbd76eb045` |
| `g4/libexec/.../4.0.4/cc1` (gcc-A) | tcc | `692c9fc1f8cf737d0e8abe0af86686fa84d62dd3c9035807531cc4deedd977d1` |
| `g4s/libexec/.../4.0.4/cc1` (gcc-B = gcc-C) | gcc-A, gcc-B | `ea8a8a8bae10e63d8264f447488d90b3d7220f0ee19be8368c7dfc989237f5fd` |
| `sysroot/usr/lib/libc.a` (musl, any path) | gcc-B | `58202246c15fa1fe9a68377a6704cabe7d236c50e3f4d6e47b0d81c59064edf8` |
| `sysroot/usr/lib/libgmp.a` (any path) | gcc-B | `74c8f43fc80aa8a4374b96c6eb54f0f12c49e83f7d0715940445d9078f9be2c8` |
| `g47/libexec/.../4.7.4/cc1plus` | gcc-B | `2101e5497f9fb925583713bc3144089835262f6eba3be8e944e001575ecf81e5` |
| `bu2/bin/as` (binutils-2.41) | gcc-4.7.4 | `da5308f95f0b881bc7b174686e302b105aa1468feaf3ced5f8976a794e903ab1` |
| `bu2/bin/ld` | gcc-4.7.4 | `8907f0ab58be00ed2ebe8055f75ee256e858a2ee72f862fdd2363db2a730d292` |
| `g10/libexec/.../10.5.0/cc1plus` | gcc-4.7.4 | `f3988ecd89a57a9550fb0bd86c2b95700cb0bac3c497686cfa0af447f3763314` |
| `g15/bin/gcc` | gcc-15 stage 2 | `64835436a39bfae810393c57b66abd4989573ee68941bc35e9135341a2a2006a` |
| `g15/libexec/.../15.2.0/cc1` | gcc-15 stage 2 | `a9f6b8a7c9ba3b2d8ae85e0031df4979def38dbf8fd05e234093bf5a8830909f` |
| `g15/libexec/.../15.2.0/cc1plus` | gcc-15 stage 2 | `545b8545bdaa081b7be3980e212bf1a316d1a9d48eab049f543d0962b614bf89` |
| `g15/lib/gcc/.../15.2.0/libgcc.a` | gcc-15 | `a2d43204f0f386c7b58f1575d892b1f70fd0067d512dbc423e899166c97513f0` |

`gcc64/HASHES` has all 43.  After a deliberate change, run with
`GCC64_REPIN=1` and copy `BUILDROOT/logs/hashes.txt` into it.

### Tests and guard (canonical run)

libc test at `-O2` under tcc-musl and every gcc: 0 failures.  tcc's
`tests2`: 83/84 under tcc-musl (`96_nodata_wanted` needs `dlsym`), 68/84
under tcc-boot2 with portable_libc; the script requires exactly these
failure lists.  gmp, mpfr, mpc `make check`: 175, 179 and 69 pass, 0
fail.  C++ test under gcc-4.7.4, 10.5.0 and 15.2.0: pass.  gcc-15's
sysroot, `as` and `ld` are the chain's, and its `-v` run executes only
chain files.  Guard: 91 configure-time probes of host tools, all
refused (34 `nm`, 18 `ld`, 18 `cc`, 8 `strip`, 8 `objdump`, 5 `gcc`);
no other guard hit.
