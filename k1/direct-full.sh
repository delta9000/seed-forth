# k1/direct-full.sh: the direct route under K1 after bash 2.05b, run by
# k1/direct.recipe with the plumbing bash as
#   bash k1/direct-full.sh JOBS=N
# from /, K1's root.  /bin and /usr/bin become links to the plumbing tools,
# as tools/plumbing-root.sh sets them up, so #!/bin/sh and config.guess's
# /usr/bin/uname reach programs this chain built.  Then gcc-direct/chain.sh
# (binutils 2.30, stage C, stage D to the GCC 4.0.4 fixed point) and
# gcc-direct/late-tools.sh (the QEMU route's late tools, each configured by
# its own configure, built by that GCC).  ladder/stage10-direct.sh then turns
# the late tools into /usr.
set -e
# The recipe runner starts programs with an empty environment.
PATH=/build-out/plumbing/bin
export PATH
jobs=${1#JOBS=}
jobs=${jobs:-2}
cd /
[ -e /bin ] || ln -s build-out/plumbing/bin /bin
mkdir -p /usr
[ -e /usr/bin ] || ln -s ../build-out/plumbing/bin /usr/bin
# chain.sh reads two of its three archives from the inputs directories the
# host route uses; on this disk they are the build-out/distfiles copies.
mkdir -p build-out/direct-gcc-inputs build-out/stage-c-inputs
[ -e build-out/direct-gcc-inputs/gcc-4.0.4-git-944765863e.tar ] ||
  ln -s ../distfiles/gcc-4.0.4-git-944765863e.tar build-out/direct-gcc-inputs/gcc-4.0.4-git-944765863e.tar
[ -e build-out/stage-c-inputs/musl-1.1.24.tar.gz ] ||
  ln -s ../distfiles/musl-1.1.24.tar.gz build-out/stage-c-inputs/musl-1.1.24.tar.gz
echo "k1: GCC chain (binutils, stage C, stage D) under K1"
/build-out/plumbing/bin/bash gcc-direct/chain.sh -j "$jobs"
grep -x '# Stage D: fixed point reached' build-out/chain/stage-d/report.txt > /dev/null ||
  { echo "k1: stage D report has no fixed point" >&2; exit 1; }
echo "k1: GCC 4.0.4 fixed point under K1; building the late tools"
/build-out/plumbing/bin/bash gcc-direct/late-tools.sh -j "$jobs"
echo "k1: late tools built by the stage-D GCC"
# K1 keeps every file in RAM: drop the source and build trees the rest of
# the route does not read (stage D's prefix, stage C's toolchain and sysroot,
# the installed late tools and every report and log stay).
rm -rf build-out/late/src build-out/chain/binutils/build build-out/chain/binutils/src \
  build-out/chain/stage-c/src build-out/chain/stage-d/src
