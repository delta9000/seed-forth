# The GCC chain on the chain's own tools

The plumbing stages ([README.md](README.md)) build make, bash, sed, grep,
gawk, coreutils, tar, gzip, patch, diffutils, oyacc and flex from the seed.
The GCC chain that follows (binutils 2.30, then stage C: GCC 4.0.4, libgcc
and musl 1.1.24, then stage D: GCC rebuilt three times to a fixed point) used
to be driven by Python recipes under a host shell and host make. These bash
scripts replace them and run on those tools alone:

| Script | Port of | Does |
|---|---|---|
| [chain-lib.sh](../gcc-direct/chain-lib.sh) | | shared helpers: pins, unpacking, hashing, file lists |
| [configure.sh](../gcc-direct/configure.sh) | configure.py | one unmodified GCC or binutils configure with seed-cc |
| [census.sh](../gcc-direct/census.sh) | census.py | every cc1 object through GCC's own Makefile; links cc1 |
| [binutils.sh](../gcc-direct/binutils.sh) | binutils.py | binutils 2.30 stage B (as, ld, ar, nm, objdump, readelf) |
| [stage-c.sh](../gcc-direct/stage-c.sh) | stage-c.py | GCC 4.0.4 driver, libgcc, musl, a hosted hello |
| [stage-d.sh](../gcc-direct/stage-d.sh) | stage-d.py | stages 2, 3 and 4 and their comparison |
| [chain.sh](../gcc-direct/chain.sh) | | the three in order, with `PATH` = `build-out/plumbing/bin` |

They are written for the bash 2.05b that [bash.kaem](bash.kaem) builds, which
has no arrays, brace expansion or `pipefail`, and call only programs the
plumbing stages install, plus seed-cc and seed-ar. The Python recipes stay in
`gcc-direct/` as the reference they were checked against.

## Running it

After `stage1.kaem`, `stage2.kaem`, `lexers.kaem` and `bash.kaem`, with the
three archives of [chain.SOURCES](chain.SOURCES) in place:

```sh
build-out/plumbing/bin/bash gcc-direct/chain.sh -j 6
```

Output goes to `build-out/chain/{binutils,stage-c,stage-d}`, each with a
`report.txt`. On korriban (24 threads, other work running) binutils took 33
minutes (before the make fix below, so mostly one job at a time), stage C
about 22 and stage D about 9.

`plumbing/chain.kaem` runs every stage from stage 1 to here, and
[tools/plumbing-root.sh](../tools/plumbing-root.sh) runs all of it inside a
root that starts with stage0-posix's `hex0-seed` as its only executable,
tracing every `execve`.

## Differences from the Python recipes

- **Inputs.** Each script unpacks the pinned archive itself (tar 1.12, gzip)
  instead of checking a pre-unpacked tree file by file. The chain cannot read
  xz, so binutils is pinned as the plain tar inside the pinned `.tar.xz`
  ([chain.SOURCES](chain.SOURCES) records the derivation). tar 1.12 predates
  the ustar prefix field, which only the 71 long names in GCC's
  `libstdc++-v3/testsuite` use; that directory is removed after unpacking.
- **One GCC tree.** Stage C configures libiberty, libcpp and gcc from one
  unpacked tree with the alloca adapter applied, rather than from symlink
  views; only libiberty compiles `alloca.c`.
- **No probe capture or frozen compiler copy.** configure.py wrapped every
  compiler call to record it and snapshotted the compiler sources;
  configure.sh runs seed-cc directly. Guards for host compilers and binutils
  are kept, as bash scripts, and log to `host-tool-attempts.log`.
- **Implicit declarations.** census.py used host GCC as a lint for calls to
  undeclared functions; census.sh passes `-Werror=implicit-function-declaration`
  to seed-cc for every cc1 object instead (220/220 compile with it).
- **binutils' top-level make.** It always fails (the WARN_ overrides do not
  reach the tool directories); binutils.sh requires only the configure and
  the three direct per-directory makes to succeed.
- **Reports** are plain text, not JSON.

## What running on the chain's tools found

Each of these made the build differ from the host-tool build until fixed:

1. **`tail -3`.** coreutils 5.0 follows the runtime's `_POSIX2_VERSION`
   (200809) and rejects the obsolete form, which gcc/configure's eh_frame probe
   uses. The probe failed and configure defined `USE_AS_TRADITIONAL_FORMAT`.
   chain-lib.sh exports `_POSIX2_VERSION=199209`, the setting coreutils 5.0
   documents for older scripts. With it, stage C's `auto-host.h` and the
   libiberty and libcpp `config.h` are byte-identical to a configure.py run
   under host sh.
2. **make ran one job at a time.** make 3.82 was configured without
   `HAVE_WAITPID`; it then counts SIGCHLDs instead, and under load ran the
   cc1 census serially despite `-j 6`. [make-3.82/config.h](make-3.82/config.h)
   now defines `HAVE_SYS_WAIT_H`, `HAVE_WAITPID` and `MAKE_JOBSERVER` (so
   recursive makes share `-j` too), as configure finds them on Linux.
3. **`ulimit -s`.** Stage D runs the stage-C cc1 with a 64 MiB stack. The
   bash config did not include `config-bot.h`, which derives `HAVE_RESOURCE`;
   [bash-2.05b/config.h](bash-2.05b/config.h) now defines it.
4. **nm and objdump in stage D.** gcc/configure looks for them in `PATH` for
   its `.subsection`, eh_frame and section-mixing probes. stage-d.py found the
   host's; with only our tools, the probes failed, stages 3 and 4 were built
   with crt objects configured differently from the stage-C ones stage 2
   links with, and stage 2 differed from stage 3 in seven executables.
   stage-d.sh puts the stage-C binutils first in `PATH`.

GCC's install step also runs `perl` for man pages, which make tolerates
failing; the chain has no perl, so no man pages are generated (the Python run
used the host's perl there).

## Result (2026-10-07)

`gcc-direct/chain.sh -j 6` with `PATH` holding only `build-out/plumbing/bin`:

- binutils: 6 of 6 tools built.
- stage C: 220 of 220 cc1 objects; libgcc, musl and the hosted hello pass;
  2 blocked host-tool attempts, both configure probes.
- stage D: stage 2 == stage 3 == stage 4, 54 installed files, 0 differ.
