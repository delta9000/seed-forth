# gcc64 — from seed-forth's tcc-0.9.27 to GCC 15.2 on amd64, via musl

`gcc64/run-gcc64.sh` continues the amd64 route past TinyCC.  From the
1,772-byte seed it reaches GCC 15.2.0 (C and C++) on x86-64 Linux, with
no host compiler, assembler or linker anywhere in the chain: every
compiler, assembler and linker is built by the stage before it.  The last
step is GCC 15.2.0's own 3-stage bootstrap, which ends in `make compare`'s
"Comparison successful" (stage2 = stage3).

```sh
gcc64/run-gcc64.sh --fetch                  # fill the source cache (needs network once)
gcc64/run-gcc64.sh                          # all stages, in build-out/gcc64 (~1.5 h, 4 cores)
gcc64/run-gcc64.sh --new DIR                # the same in a fresh DIR
BUILDROOT=DIR gcc64/run-gcc64.sh stage11 stage12   # re-run stages in place
VERIFY_GCC64=1 ./verify.sh                  # as verify.sh's opt-in step 10
```

It is not part of `check-all.sh` (too slow).  `verify.sh` runs it only
with `VERIFY_GCC64=1`, from its own step 9's `tcc-boot2`, and reports
SKIP otherwise.

## Stage-0 selection and verification scope

Standalone `run-gcc64.sh` now builds stage 0 through the direct raw-input
`tests/tcc/kernel-route-check.sh` route: Forth-built helpers unpack and
patch the original TinyCC source, and Forth directly compiles TinyCC.
There is no pnut compiler executable in this default path. Artifact pins
are read from `tools/tcc.recipe`; the final TinyCC/runtime bytes match the
historically verified control handoff.

`GCC64_STAGE0=WORK_ROOT` can reuse a finished direct or named pnut-control
kit. It checks `tcc-boot2`, `crt1.o`, `libc.a`, and `libtcc1.a` before copying
it. This verifies the supplied artifacts, not their compiler provenance.
The `verify.sh` opt-in continuation still explicitly supplies its control
kit. The full GCC 15.2 timings and results below were recorded before
this default stage-0 migration; they are not a new full-chain rebuild.

## Bridge from the direct route (no TinyCC)

The `bridge` stage replaces stages 0 to 5 with the direct route's GCC 4.0.4
(`gcc-direct/stage-d.sh`), whose first generation was compiled by the Forth
C compiler with no TinyCC. It leaves stage 6 onward the layout stages 4 and 5
leave:

```sh
GCC64_DIRECT=STAGE_D_WORK GCC64_OYACC=OYACC GCC64_FLEX=FLEX \
    gcc64/run-gcc64.sh --new DIR      # bridge stage6 ... stage12
```

`GCC64_DIRECT` is a finished stage-D work directory. Its report
(`report.txt` from `stage-d.sh`, or `report.json` from `stage-d.py`) must
record the stage 2 = 3 = 4 fixed point, and `prefix/` must hash to that
fixed point. Stage C's toolchain and sysroot are found by asking that GCC
for its configured `as` and `libc.a`. `GCC64_OYACC` and `GCC64_FLEX` are the
Forth-built oyacc and flex 2.5.11 from the lexers stage. The bridge builds:

| Path | What | Built by |
|---|---|---|
| `bu/` | binutils-2.30, configured exactly as stage 4 (`BU230_CONF`, `-g0`) | the direct GCC, with stage C's Forth-built as/ld/ar |
| `tools/bin/` | oyacc and flex 2.5.11, copied | the Forth compiler |
| `sysroot/` | stage C's musl-1.1.24, copied (stage 7 replaces it) | the Forth-built GCC |
| `g4/` | gcc-A, by the same `build-gcc4.sh` as stage 5 | the direct GCC |

After the bridge, `build-gcc4.sh` (stage 6 too) uses oyacc and flex 2.5.11
instead of host bison and flex-2.6.4 (`GCC4_YACC`, `GCC4_LEX`), with the
`gcc/system.h` YYBYACC exemption stage D applies (`GCC4_BYACC=1`). No tcc,
host bison or host m4 runs before stage 7. `bridge/inputs.txt` records the
inputs' sha256. `bridge/direct.env` marks the BUILDROOT as bridged, for
stage 6 and the pins step.

**Result** (cloud run, 2026-10-07, at the canonical BUILDROOT). The bridge
and stages 6 to 12 passed, with all their tests. Stage 6's gcc-B = gcc-C
holds. Stage 7's gmp, mpfr and mpc `make check` reported 0 failures. GCC
15.2's bootstrap reported "Comparison successful". The pins step reported
23 as pinned and 0 differing. The 13 outputs the bridge builds differently
(binutils-2.30, flex, gcc-A, and gcc-B's executables, which link route D's
musl) were not compared. Against the TinyCC route:

- **GCC 15.2.0 is byte-identical**: `g15/bin/gcc`, `cc1`, `cc1plus`,
  `libgcc.a` and `libstdc++.a` match the pins that route T's run recorded.
  Two first compilers that share no code, tcc 0.9.27 and the Forth
  compiler, lead to the same final GCC.
- **12 more identical** along the way: gcc-B's
  `crtbegin.o`/`crtend.o`, the stage-7 sysroot (`libc.a`, `libgmp.a`,
  `libmpfr.a`, `libmpc.a`), `g47/bin/gcc`, gcc-4.7.4's and gcc-10.5.0's
  `libstdc++.a`, and binutils-2.41's `as`, `ld` and `ar`.
- **6 differ, both causes found** (pinned as `direct` in `HASHES`):
  - gcc-B's `libgcc.a` differs in three members (`_eprintf.o`,
    `unwind-dw2.o`, `unwind-dw2-fde-glibc.o`), and only in debug info. With
    `--strip-debug` they are identical. Their DWARF line numbers point into
    `bits/alltypes.h`. Route T's copy carries tcc's 23-line `va_list` patch
    (`patches/gcc64/musl-1.1.24`); route D's musl headers are pristine.
  - gcc-4.7.4's `cc1`/`cc1plus` and gcc-10.5.0's `gcc`/`cc1`/`cc1plus` also
    differ in code, from the **assembler**. Given the same `.s`, gcc-B's
    output for gcc-4.7.4's `config/i386/i386.c` (byte-identical in both
    routes), binutils-2.30 `as` built by tcc and `as` built by the Forth
    compiler (stage B) produce one object. `as` built by GCC 4.0.4 (at -O0
    or -O2) and `as` built by host GCC 13 produce another. They choose
    different branch encodings (`je rel8` vs `je rel32`, absorbed by
    alignment padding). The two encodings mean the same thing.
    gcc-10.5.0's binaries inherit the difference through gcc-4.7.4's
    `libgcc.a`, which that `as` also assembles. That two C
    compilers which share no code disagree with two GCCs suggests a
    C-semantics gap that tcc 0.9.27 and the Forth compiler share, or
    undefined behaviour in gas 2.30 that GCC compiles differently. This
    is not investigated yet.

In the bridged run, binutils-2.41 is still identical to route T's
(`bu2/`), so from stage 9 on both routes use one assembler.

## The chain

```
seed-forth (1,772 B)                                  tests/tcc/kernel-route-check.sh
  -> Forth-built patch/archive helpers -> direct tcc-seed -> tcc-boot0..3
                                            tcc-boot2 = tcc-boot3 (portable_libc)
stage 1   tcc-boot2   builds tcc-p0   (tcc + lb patches; "bridge" libc64: real ldexp/strtod)
stage 2   tcc-p0      builds musl-1, then tcc-1 against it
          tcc-k       builds musl-(k+1), then tcc-(k+1)
                      fixed point: musl-2 = musl-3, tcc-2 = tcc-3       => tcc-musl (tc/)
stage 3   tcc's tests/tests2 under tcc-boot2 and tcc-musl
stage 4   tcc-musl    builds binutils-2.30 (as, ld, ar, ...)            => bu/
stage 5   tcc-musl    builds flex-2.6.4, and gcc-4.0.4 (C) "gcc-A"      => g4/
stage 6   gcc-A       builds gcc-4.0.4 "gcc-B"; gcc-B builds "gcc-C"; B = C  => g4s/
stage 7   gcc-B       builds musl-1.1.24 again (the sysroot), gmp, mpfr, mpc (+ make check)
stage 8   gcc-B       builds gcc-4.7.4 (C, C++)                          => g47/
stage 9   gcc-4.7.4   builds binutils-2.41                               => bu2/
stage 10  gcc-4.7.4   builds gcc-10.5.0 (C, C++), with binutils-2.41     => g10/
stage 11  gcc-10.5.0  seeds gcc-15.2.0's 3-stage bootstrap; stage2 = stage3  => g15/
stage 12  every gcc compiles and runs the tests; gcc-15's sysroot, as, ld are the chain's
pins      every key output against gcc64/HASHES
```

Stages 4 and 5 link with tcc's own linker (tcc is compiler, assembler and
linker in one); gcc-4.0.4 then uses binutils-2.30, which tcc built.  The
sysroot's libraries (musl, gmp, mpfr, mpc) are built by gcc-B in stage 7
and are not rebuilt later (see "Open issues").

## Stages

Timings: the historical canonical clean control run (below) on 4 cores,
`JOBS=4`, in wall-clock seconds. Stage 0 in this table used pnut; it does
not time the current direct route.  `check-all.sh` and `verify.sh` ran alongside it
during stages 10–11, so those two are somewhat slow.

| Stage | What | Built by | Seconds |
|---|---|---|---:|
| 0 (historical control) | seed-forth → pnut → tcc-0.9.27 x86_64, `tcc-boot2 = tcc-boot3` | seed-forth, pnut | 12 |
| 1 | tcc-p0 | tcc-boot2 (portable_libc + bridge) | 1 |
| 2 | musl-1.1.24 and tcc, to a fixed point | tcc-p0, then each tcc | 19 |
| 3 | tcc `tests/tests2` | tcc-boot2, tcc-musl | 3 |
| 4 | binutils-2.30 | tcc-musl | 32 |
| 5 | flex-2.6.4, gcc-4.0.4 (gcc-A) | tcc-musl (+ binutils-2.30 for gcc-A's own output) | 37 |
| 6 | gcc-B, gcc-C (B = C) | gcc-A, gcc-B | 282 |
| 7 | musl-1.1.24, gmp-6.2.1, mpfr-4.1.0, mpc-1.2.1, each with `make check` | gcc-B + binutils-2.30 | 154 |
| 8 | gcc-4.7.4 (C, C++) | gcc-B + binutils-2.30 | 191 |
| 9 | binutils-2.41 | gcc-4.7.4 | 57 |
| 10 | gcc-10.5.0 (C, C++) | gcc-4.7.4 + binutils-2.41 | 345 |
| 11 | gcc-15.2.0 (C, C++), 3-stage bootstrap | gcc-10.5.0, then itself twice | 4,851 |
| 12 | verify every gcc | — | 3 |
| | **total** | | **5,987 (~100 min)** |

## What is checked

- **Fixed points, enforced by the script:** musl-2 = musl-3 and
  tcc-2 = tcc-3 (stage 2); gcc-B = gcc-C byte for byte in `bin/gcc`,
  `bin/cpp`, `cc1`, `collect2`, `libgcc.a`, `crtbegin.o`, `crtend.o`
  (stage 6); gcc-15.2.0's "Comparison successful" (stage 11); and, in
  stage 0, `tcc-boot2 = tcc-boot3` with matching objects. The pnut
  self-hosting fixed point belongs to the separately retained control.
- **Tests:** `tests/gcc64/libc-test.c` (printf of 64-bit and floats,
  malloc, setjmp, qsort, strtod, `%.20Lg`, libm, varargs, stdio,
  fork/exec, sscanf) under tcc-musl and, at `-O2`, under gcc-A, gcc-B,
  gcc-B with the gcc-built musl, gcc-4.7.4, gcc-10.5.0 and gcc-15.2.0.
  tcc's `tests2`: under tcc-musl 83 of 84 pass (`96_nodata_wanted` needs
  `-run` and `dlsym`, which a static libc lacks); under tcc-boot2 with
  portable_libc 68 of 84; the script requires exactly these failure
  lists.  Stage 4: GNU ld links a tcc object against musl, and GNU as
  and tcc's assembler agree instruction for instruction on musl's
  `fenv.s`.  Stage 7: gmp, mpfr and mpc `make check`, 0 failures.
  Stages 8, 10, 11: `tests/gcc64/cxx-test.cc` (virtual dispatch,
  templates, exceptions, `std::map`/`vector`/`ostringstream`).  Stage 12:
  every gcc compiles and runs `tests/gcc64/{hello,t64,flt}.c` (and the
  C++ test from 4.7.4 on); gcc-15's `-print-sysroot`,
  `-print-prog-name=as` and `=ld` are the chain's, and every program its
  `-v` run executes lies under `BUILDROOT`.
- **Pins:** `gcc64/HASHES`, see "Reproducibility".
- **Guard:** see "Trust".

## Sources

`gcc64/SOURCES` lists every source with its sha256 and URLs: upstream
first (live-bootstrap's URL where our file is byte-identical to
live-bootstrap's), then the Ubuntu archive URL the canonical run actually
fetched from (this sandbox cannot reach kernel.org, gnu.org or
musl.libc.org).  Files go into `GCC64_CACHE` (default
`build-out/gcc64-cache`, gitignored); the script checks every file's
sha256 before any stage runs and refuses a mismatch.  With the cache
full it needs no network.  Nothing is vendored in the repository.

| Source | vs live-bootstrap (`b1ceced7`) |
|---|---|
| musl-1.1.24, binutils-2.30, flex-2.6.4, mpfr-4.1.0, mpc-1.2.1, binutils-2.41, gcc-10.5.0, gcc-15.2.0 | same sha256 |
| gmp-6.2.1 | Debian's `+dfsg` repack (non-free docs removed), not lb's `gmp-6.2.1.tar.xz` |
| gcc-4.7.4 | a `.tar.xz` from Ubuntu's orig tarball; lb pins the `.tar.bz2`.  The uncompressed tar's sha256 is in `SOURCES` for comparison |
| gcc-4.0.4 | `git archive` of gcc-mirror's `releases/gcc-4.0.4` tag, commit `944765863eec`; lb uses `gcc-core-4.0.4.tar.bz2`.  The export has no pregenerated parsers, so host bison makes them.  `SOURCES` pins the uncompressed tar, which `git archive` reproduces exactly (checked by re-cloning) |
| tcc-0.9.27, portable_libc | from stage 0 (pnut's vendored tarball and `vendor/pnut` at `abc34a5`, source pins in `tools/tcc-raw-inputs.sha256`, artifact pins in `tools/tcc.recipe`); lb uses savannah's `tcc-0.9.27.tar.bz2` |

## Patches

All in `patches/gcc64/`; its README says what each does and why, and
every file has a provenance header.  In short:

| Patches | From | Why |
|---|---|---|
| `libc64/01-bridge.diff` | ours | stage 1 only: real `ldexp`/`strtod` and a 1 GiB heap in portable_libc so tcc-p0 can build musl |
| `tcc/01..03` + `tcc-simple/*` | live-bootstrap | `[static N]`, weak symbols in `tcc -ar`, static by default, `tcc -ar` open order, a NULL check |
| `tcc/10`, `tcc/11` | ours | link libc again after libtcc1; never unlink `/dev/...` |
| `musl-1.1.24/01..04` | ours | tcc on x86_64: syscall registers, `va_list`, `stmxcsr`/`ldmxcsr` as `.byte`, no `@PLT` |
| `musl-1.1.24/05`, `06` | live-bootstrap | empty archives; `errno` across `madvise` |
| `musl-gcc/01-basename-c23.diff` | ours | gcc-15 (C23) vs musl-1.1.24's `char *basename();` |
| `gcc-4.0.4/01-collect2-unlink-if-ordinary.diff` + 3 `sed`s | ours; the `sed`s are lb's | collect2 deleted `/dev/null` as root; tcc, musl, new bison |
| `gcc-4.7.4/*` (12) | live-bootstrap | musl support; what gcc-10's build needs from gcc-4.7 |
| `gcc-10.5.0/*` (3) | live-bootstrap | `cpuid.h`/`-fno-pic`, XF mode, a flag gcc-4.7 lacks |

gcc-15.2.0 needs none (live-bootstrap has none either).

## Trust

What the chain runs that it did not build:

- **The seed and the sources.**  Stage 0 starts from the 1,772-byte seed
  (via stage0-posix's `hex0-seed`), Forth/compiler/helper sources, and the
  raw TinyCC archive/portable libc retained in `vendor/pnut`. The default
  stage does not compile pnut. Every later source is sha256-pinned in
  `SOURCES`.
- **Host build glue, never a compiler, assembler or linker.**  `PATH` is
  exactly `BUILDROOT/guard:BUILDROOT/hostbin` plus the stage's own
  chain-built `bin/` directories, so `/usr/bin` is never searched.
  `hostbin/` holds symlinks to this fixed list (`HOSTTOOLS` in the
  script): `bash sh make sed grep egrep fgrep awk mawk tr cut sort uniq
  comm join paste cat tac head tail wc cp mv rm rmdir mkdir ln ls touch
  chmod install readlink realpath basename dirname pwd tar gzip gunzip
  zcat xz unxz bzip2 patch diff cmp sha256sum md5sum cksum find xargs
  expr env uname date sleep test [ true false printf echo tee mktemp od
  dd du stat id hostname nproc getconf timeout nice seq split tsort fold
  nl sync which bison m4 python3`, plus the retained `git bc unshare mount`
  allowances for setup/compatibility.  Also reachable by absolute path: `/bin/sh`
  (`#!` lines, `system()`), `/usr/bin/env`, and libtool's probes of
  `file` and `ldconfig`.  `python3` verifies raw stage-0 inputs/inventories and runs
  `simple-patch.py` for later source replacements; stage-0 archive
  extraction and exact patching use Forth-built helpers. `curl` and `git`
  fetch sources
  (with the host `PATH`).
- **Two host code generators.**  Host `bison` writes gcc-4.0.4's C parser
  (`c-parse.c`) and `gengtype-yacc.c` (the git export has none), and
  flex (chain-built) runs the host `m4` at run time for gcc-4.0.4's
  `gengtype-lex.l`.
- **Pregenerated files from the tarballs.**  Unlike live-bootstrap, we
  do not regenerate `configure` scripts, `Makefile.in`s, bison/flex
  outputs, `opcodes` tables or gperf outputs; we use the tarballs' own
  (except gcc-4.0.4's parsers, above).
- **Guard results.**  `BUILDROOT/guard/` shadows every host
  compiler-like name (`gcc cc c89 c99 ld as ar ranlib cpp g++ c++ nm
  strip objcopy objdump readelf ... tcc clang`) with a script that
  refuses (exit 99) and logs.  As root (or mapped root in a user
  namespace), the script also runs in a private mount namespace in which
  the same refusing script is bind-mounted over every host compiler,
  assembler and linker reachable by absolute path (`/lib/cpp`,
  `/usr/bin/gcc*`, `/usr/bin/as`, `/usr/bin/ld*`, ...), the host gcc and
  llvm library trees are hidden under an empty tmpfs, and `/dev/null` is
  bind-mounted onto itself so nothing can delete it.  Configure scripts
  probe for tools by name; those probes hit the guard and are refused
  (the canonical run: 91 refused probes in all: 34 `nm`, 18 `ld`, 18 `cc`, 8 `strip`, 8 `objdump`, 5 `gcc`, listed with their working directory in `logs/guard-probes.log`).  The script fails if any guard hit is
  not a configure-time probe (`conftest`, `-v`, `--version`, ...).  An
  `strace -f` audit of an earlier full run (`GCC64_TRACE=FILE`, every
  `execve`) found no host compiler, assembler or linker executed; before
  the absolute-path guard existed, it found autoconf's `/lib/cpp`
  fallback running host `cc1plus` in two sub-configures, which is why
  `CXXCPP` is now exported and the guard covers absolute paths.  With the
  guard in place the stage hashes were unchanged.

## Reproducibility

Every stage is deterministic.  Two independent from-scratch runs at the
same `BUILDROOT` produced all 43 artifacts in `gcc64/HASHES`
bit for bit, from musl and tcc to gcc-15's `cc1plus`: the development
run of the scratch kit these scripts came from, and a run of the
repository's scripts on 2026-09-27 (in a fresh directory at the same
path, with the old one moved away).  Every fixed point and test result
matched too.

But most artifacts embed absolute paths under `BUILDROOT`: tcc's
`CONFIG_TCCDIR` and include paths, every gcc's `--prefix` and
`--with-sysroot`, binutils' prefix, flex's path to `m4`, and `__FILE__`
strings of the build tree.  So their hashes depend on `BUILDROOT`.  A
second build of stages 0–7 in a different directory (`JOBS=2`
instead of 4) gave:

- the same bytes: `tcc-boot2` (stage 0 pins only relative paths), musl's
  `libc.a` whether built by tcc (`m1/`, `tc/`) or by gcc-B (`sysroot/`),
  `libgmp.a`, and gcc-B's `crtbegin.o`/`crtend.o`;
- different bytes: every tcc after `tcc-boot2`, `libtcc1.a` (tcc records
  the absolute source path), binutils-2.30, flex, every gcc-4.0.4 binary,
  gcc-B's `libgcc.a` (debug info or `__FILE__`, not investigated), `libmpfr.a` and `libmpc.a`.

Every later stage is built by one of these path-dependent compilers
into prefixes under `BUILDROOT`, so we did not spend the ~1.5 h to test
stages 8–11 at a second path; they are recorded as path-dependent.

`gcc64/HASHES` therefore marks each hash `any` (holds for every
`BUILDROOT`) or `root` (holds for the canonical `BUILDROOT`, recorded on
its `root` line).  The pins step enforces `any` hashes everywhere and
`root` hashes only at that path; elsewhere it reports them as not
comparable.  The fixed points above are enforced everywhere.  To
reproduce every hash, read the canonical path from the checked-in manifest
(any path works; the `root` hashes belong to that recorded path):

```sh
canonical_root=$(sed -n 's/^root //p' gcc64/HASHES)
gcc64/run-gcc64.sh --new "$canonical_root"
```

## Open issues

- **The sysroot's libraries are gcc-4.0.4's for good.**  musl-1.1.24,
  gmp, mpfr and mpc are built once, by gcc-B, and never rebuilt by
  gcc-10 or gcc-15; binutils-2.41 (the final `as`/`ld`) is gcc-4.7.4's
  build.  A "stage 13" would have gcc-15 rebuild musl, binutils-2.41 and
  then itself once more, and compare.
- **musl-1.1.24 throughout.**  live-bootstrap moves on to musl-1.2.5.
- **Three sources are not live-bootstrap's bytes** (gmp `+dfsg`,
  gcc-4.7.4 `.xz`, gcc-4.0.4 git export); all three go away when
  gnu.org mirrors are reachable.
- **No regeneration** of configure scripts and other generated files,
  and **host bison and m4** as code generators (see "Trust").
- **Path-dependent hashes** (see "Reproducibility"): building at a fixed
  path (for example inside a chroot or the script's mount namespace)
  or with `-ffile-prefix-map` and relative prefixes would make them
  path-independent.
- The canonical hashes come from one machine (x86-64, 4 cores); another
  kernel or CPU has not been tried.

## Next step: chain-built build glue

The remaining host programs are build glue.  Replacing them follows
live-bootstrap's model, and `handoff.sh` already reproduces the
starting point from the seed: stage0-posix's `AMD64/bin`, including
`kaem` and mescc-tools-extra (`catm`, `cp`, `chmod`, `mkdir`, `rm`,
`sha256sum`, `untar`, `ungz`, `unbz2`, `unxz`, `replace`, `match`, ...).

1. **Before bash.** Stage 0 now runs through the seed-built recipe
   runner and Forth-built raw-source helpers. Drive stages 1–2 with
   chain-built scripting tools, as
   live-bootstrap's `steps/tcc-0.9.27/pass1.kaem` does: extraction with
   `ungz`/`untar`/`unxz`, hashes with `sha256sum`, and live-bootstrap's
   `simple-patch` (built by M2-Planet) instead of `python3
   simple-patch.py`.  Our unified diffs then need a chain-built `patch`
   first, or rewriting as before/after pairs.
2. **With tcc-musl, before binutils** (live-bootstrap's order, each
   built by tcc): make, patch, gzip, tar, sed, bzip2, coreutils, a
   yacc, bash; then grep, m4, flex, bison, diffutils, gawk, xz.  Our
   x86_64 tcc-musl already compiles musl, binutils, flex and gcc-4.0.4,
   so the risk is low.
3. **The rest of `HOSTTOOLS`:** `python3` goes with step 1; `timeout`,
   `hostname`, `nproc`, `getconf`, `od` come with coreutils/findutils;
   source acquisition and namespace/image setup remain outside the
   stage-0 seed execution boundary; `/bin/sh` becomes the chain-built bash.
4. **No perl yet,** because nothing is regenerated; regenerating
   autotools output would need live-bootstrap's perl sequence too.
5. **A chroot** of `BUILDROOT` with only chain-built `/bin`, as
   live-bootstrap does; the mount namespace is a halfway step.  A fixed
   path there would also make every hash path-independent.

## Files

| Path | What |
|---|---|
| `gcc64/run-gcc64.sh` | the driver: stages 0–12, pins, guard, namespace |
| `gcc64/build-gcc4.sh`, `build-gcc47.sh`, `build-gcc10.sh`, `build-gcc15.sh` | one GCC build each (called by the driver) |
| `gcc64/mktcc.sh` | one tcc (+ `libtcc1.a`) against a given musl |
| `gcc64/simple-patch.py` | live-bootstrap's `simple-patch` semantics (replace a unique before-text) |
| `gcc64/SOURCES`, `gcc64/HASHES` | source pins; artifact pins |
| `patches/gcc64/` | patches, with a README |
| `tests/gcc64/` | `libc-test.c`, `cxx-test.cc`, `hello.c`, `t64.c`, `flt.c` |
| `BUILDROOT/logs/` | per-stage logs, `timings.txt`, `hashes.txt`, `guard-probes.log` |
