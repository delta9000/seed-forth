# The late tools, built by the direct route's GCC

The QEMU route gets its modern userland in two steps. Ladder stage 9
replays host-captured builds of ten packages (`tools/capture-build.py`: the
host ran each `./configure` and `make` once, and the ladder replays the
compiler calls with the captured `config.h` and other configure output as
fixtures). Then [ladder/stage10.sh](../ladder/stage10.sh) configures the
rest with those ten. The host capture is the step this replaces.

[gcc-direct/late-tools.sh](../gcc-direct/late-tools.sh) builds all of them
with nothing captured. Each package's own `./configure` runs under the
plumbing bash 2.05b, its Makefile under the plumbing make 3.82, and its C
goes through the stage-D GCC 4.0.4 with the stage-C musl 1.1.24 and
binutils 2.30. The packages and pins are in [late.SOURCES](late.SOURCES):

| ladder stage 9 (captured) | ladder stage 10 (configured) |
|---|---|
| gzip 1.13, bash 5.2.37, tar 1.35, sed 4.9, grep 3.11, gawk 5.3.1, coreutils 9.5, patch 2.7.6, xz 5.6.3 | make 4.4.1, bzip2 1.0.8, diffutils 3.10, findutils 4.10.0, m4 1.4.19, bison 3.8.2, flex 2.6.4, bc 1.07.1 |

(stage 9's make 3.82 is not rebuilt: the plumbing stages already have it.)
Configure arguments are the ones the capture or stage10.sh used. The only
patch is stage 10's `bc-1.07.1/01-fix-libmath-sed.diff` (no `ed`); the
diffutils patch is a tcc workaround GCC does not need.

## Running it

After [gcc-direct/chain.sh](../gcc-direct/chain.sh), with the 17 archives
in `build-out/distfiles`:

```sh
build-out/plumbing/bin/bash gcc-direct/late-tools.sh -j 8     # into build-out/late
build-out/plumbing/bin/bash gcc-direct/late-check.sh -j 8     # each package's make check
```

On the host, `#!/bin/sh` scripts and `system()` still reach the host's
`/bin/sh`, and config.guess runs `/usr/bin/uname` by absolute path. A host
run traced 150-odd such calls. [tools/late-root.sh](../tools/late-root.sh)
removes them: it copies a finished `tools/plumbing-root.sh` root (the one
that started with `hex0-seed` as its only executable), checks that the copy
holds no executable the chain run did not write, and runs late-tools.sh in
it through bwrap under `strace -f -e trace=execve`; `CHECK=1` adds the test
suites.

```sh
CHECK=1 JOBS=8 tools/late-root.sh build-out/plumbing-root build-out/late-root
```

## Result (2026-10-07, korriban)

In the root: all 17 packages built in 409 s (configure is most of it).
76,974 successful `execve` calls; one is the host's `bwrap`, the rest are
programs the chain wrote (the plumbing tools, the stage-D GCC, the stage-C
binutils, configure's `conftest`s and the packages' own build programs). The
262 failed lookups are config.guess probing other systems' `uname` variants,
the bc build running its `fix-libmath_h` (no `#!` line, so bash runs it), and
packages' tests of their own uninstalled programs.

Every installed program is a static x86-64 ELF whose `.comment` is
`GCC: (GNU) 4.0.4`; all 17 answer `--version`.

## Test suites

`late-check.sh` runs `make -k check` with the late tools first in `PATH`,
bash 5.2 as `/bin/sh` and as make's `SHELL` and `CONFIG_SHELL` (as after
stage 10; the suites' scripts use `unalias`, `<(...)` and `echo -e`, which
the chain's bash 2.05b lacks). In the root:

| package | result |
|---|---|
| grep | 282 pass, 69 skip, 2 xfail, 0 fail |
| sed | 210 pass, 50 skip, 0 fail |
| m4 | 233 pass, 34 skip, 0 fail |
| diffutils | 203 pass, 37 skip, 0 fail |
| patch | 42 pass, 2 xfail, 0 fail |
| xz | 16 pass, 3 skip, 0 fail |
| tar | 215 autotest tests pass |
| bison | 377 autotest tests pass (399 skipped: C++, D, Java), 7 more pass |
| findutils | 302 pass, 61 skip, 1 fail: `test-c32ispunct` (musl, below) |
| gzip | 52 pass, 2 skip, 2 fail: `zmore`, and `help-version` through it (no `more`) |
| coreutils | 1638 pass, 614 skip, 15 fail, 6 error (below) |
| gawk | all but 3: `commas` (no `en_US` locale), `nonfatal3` (no network), `clos1way6` (output order of a two-way pipe) |
| bash | diffs only where the root lacks `/etc`, `/dev/tty`, `locale` and locales, in output ordering (`run-trap`, `run-execscript`), and in `run-cond`'s `[[=d=]]` / `[[.o.]]` regex classes, which musl 1.1.24's regcomp does not support |
| make | suite not run: it needs perl |
| flex | not run: building its tests needs a C++ compiler (`g++`) |
| bc | no test suite |

coreutils' failures and errors, each read from its log:

- `chgrp/*`, `test-chown`, `test-fchownat`, `test-lchown`, `id/uid`, `id/zero`, `whoami`, `help-version` (through `whoami`): the bwrap
  user namespace maps one uid and one gid and the root has no
  `/etc/passwd` or `/etc/group`.
- `rm-readdir-fail`, `nfs-removal-race`, `no-mtab-status`, `skip-duplicates`,
  `getxattr-speedup`: set-up failures; they build an `LD_PRELOAD` shared
  library, and this toolchain is static only.
- `test-localtime_r`, `test-localtime_r-mt`: no `/usr/share/zoneinfo` in the
  root (both pass when the same binaries run on the host).
- `chown/separator`: its set-up runs `id` for the user name, which has none
  here.
- `test-canonicalize`, `test-c32ispunct`: gnulib's tests expect newer musl
  when `MUSL_LIBC` is set (realpath keeping `//`, `iswpunct` of U+E003A TAG
  COLON). Both fail the same way when run on the host.

The attributions above come from reading each log; none of the failures was
checked against a second compiler, so a GCC 4.0.4 miscompilation hiding
behind one of them is not ruled out.

## What differs from the captured build

The captured `config.h` files in `ladder/*/fixtures` against this run's:

- **Compiler.** GCC 4.0.4 has VLAs (`HAVE_C_VARARRAYS`, no
  `__STDC_NO_VLA__`) and `visibility` (`HAVE_VISIBILITY 1`), which tcc
  lacks. It fails autoconf's `restrict` probe (`static or type qualifiers in
  abstract declarator`, a GCC 4.0 limit), so `restrict` is defined empty
  where tcc took `__restrict__`.
- **bash `HAVE_SYS_ERRLIST`.** Its link probe only reads `sys_errlist`, and
  at `-O2` GCC drops the read, so the probe links against musl, which has no
  `sys_errlist`. bash only uses it without `strerror`, which musl has, so the
  built bash is unaffected.
- **The environment.** tar has no `REMOTE_SHELL` (the host had
  `/usr/bin/rsh`); bash's `DEFAULT_MAIL_DIRECTORY` is `unknown` (no
  `/var/mail`); coreutils and tar find a fully working `getcwd` for long
  names in the root.
- Every other line of the captured `config.h` files matches.

Three fixes were needed to get there, all in late-tools.sh:

1. **The build triple.** config.guess tells musl from glibc by whether
   `<stdarg.h>` defines musl's `__DEFINED_va_list`; GCC's own `stdarg.h` is
   found first, so it answered `x86_64-pc-linux-gnu`, and gnulib then
   assumed glibc's thread-safe `setlocale` (`test-setlocale_null-mt-all`
   failed in grep, sed, findutils, diffutils and coreutils). The script
   passes `--build=x86_64-pc-linux-musl`.
2. **Script paths.** configure records the shell and tools it ran with.
   Inside the root `/bin/sh` is the plumbing bash, so the script names it
   `/bin/sh`, and the 33 installed scripts that begin `#!/bin/sh` say so
   instead of naming a path into `build-out/plumbing`.
   zgrep and updatedb also keep the `grep` and `sort` configure found; grep
   2.4 lacks `--label` and coreutils 5.0's sort lacks `-z`, so grep and sed
   are built before gzip, and gzip and findutils are given the late grep
   and sort.
3. **`/dev`.** With only `/dev/null` in the root, bash configured without
   `/dev/fd` and `/dev/stdin`; late-root.sh gives bwrap a minimal `/dev`.

## Not done (and done since)

- Stage 10's shims (`hostname`, `getconf`, `which`, `awk` and `install`
  links) are for gcc64's scripts and are left to whatever runs next.
- No second run compared for reproducibility; the absolute prefix
  (`/build-out/late/usr`) is compiled into several programs, so a different
  output directory gives different bytes.
- Under K1 (`k1/run-chain.sh --direct-linux`, see k1/README.md) the same
  script builds them as root, which tar and coreutils accept only with
  `FORCE_UNSAFE_CONFIGURE=1`, which late-tools.sh sets.
