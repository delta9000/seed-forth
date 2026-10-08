#!/bin/bash
# late-tools.sh -- the QEMU route's late tools, built by the direct route's GCC.
#
# Usage (from the repository root, after gcc-direct/chain.sh):
#   build-out/plumbing/bin/bash gcc-direct/late-tools.sh [-j JOBS]
#       [--chain DIR] [--distfiles DIR] [OUT]
#
# The QEMU route gets make 4.4.1, bash 5.2, coreutils 9.5, sed, grep, gawk,
# tar, gzip, xz, patch and the rest by replaying host-captured builds
# (ladder stage 9, tools/capture-build.py) and then configuring the rest
# under those (ladder/stage10.sh).  This script builds the same packages,
# pinned in plumbing/late.SOURCES, with nothing captured: each one's own
# ./configure runs under the plumbing bash 2.05b, its Makefile under the
# plumbing make 3.82, and its C code goes through the stage-D GCC 4.0.4
# (CHAIN/stage-d/prefix) with the stage-C musl and binutils.
#
# PATH is build-out/plumbing/bin, then the stage-C binutils, then OUT/usr/bin,
# so a plumbing tool always wins over a late one; the late ones are only
# found for what the plumbing stages lack (m4 for bison and flex, xz for the
# two .tar.xz archives, bison's yacc for bc).  Output goes to OUT (default
# build-out/late): OUT/src (builds), OUT/usr (installed), OUT/logs and
# OUT/report.txt.  A package whose OUT/logs/NAME.done exists is skipped.
set -e
PROG=late-tools
ROOT=$(cd "${0%/*}/.." && pwd)
. "$ROOT/gcc-direct/chain-lib.sh"

jobs=6 out= chain=$ROOT/build-out/chain distfiles=$ROOT/build-out/distfiles
while [ $# -gt 0 ]; do
  case $1 in
    -j|--jobs) jobs=$2; shift 2 ;;
    --chain) chain=$2; shift 2 ;;
    --distfiles) distfiles=$2; shift 2 ;;
    -*) die "unknown option $1" ;;
    *) out=$1; shift ;;
  esac
done
BIN=$ROOT/build-out/plumbing/bin
PATH=$BIN
export PATH
chain=$(absdir "$chain")
distfiles=$(absdir "$distfiles")
out=${out:-$ROOT/build-out/late}
mkdir -p "$out/src" "$out/usr/bin" "$out/logs"
out=$(absdir "$out")
P=$out/usr
TOOLS=$chain/stage-c/toolchain
CC=$chain/stage-d/prefix/bin/gcc
require_tool bash "$BIN/bash"
require_tool gcc "$CC"
require_tool as "$TOOLS/as"

PATH=$BIN:$TOOLS:$P/bin
# configure runs under the plumbing bash either way.  Inside the chain root
# (tools/late-root.sh) /bin/sh is that bash, so name it /bin/sh, as configure
# would on its own: the scripts the packages install (zgrep, xzdiff, egrep ...)
# then start with #!/bin/sh rather than a path into build-out/plumbing.
if cmp -s /bin/sh "$BIN/bash"; then CONFIG_SHELL=/bin/sh; else CONFIG_SHELL=$BIN/bash; fi
SHELL=$CONFIG_SHELL
HOME=$out
TZ=UTC0
SOURCE_DATE_EPOCH=0
CFLAGS=-O2
LDFLAGS=-static
AR=$TOOLS/ar RANLIB=$TOOLS/ranlib NM=$TOOLS/nm
CC_FOR_BUILD=$CC BUILD_CC=$CC
# config.guess tells musl from glibc by whether <stdarg.h> defines musl's
# __DEFINED_va_list; GCC's own stdarg.h is found first, so it would say
# x86_64-pc-linux-gnu, and gnulib would then assume glibc's thread-safe
# setlocale.  Name the C library instead.
BUILD=x86_64-pc-linux-musl
# K1 runs everything as root, and tar's and coreutils' configure refuse to
# run as root unless told this is deliberate.
FORCE_UNSAFE_CONFIGURE=1
export FORCE_UNSAFE_CONFIGURE
export PATH CONFIG_SHELL SHELL HOME TZ SOURCE_DATE_EPOCH CC CFLAGS LDFLAGS AR RANLIB NM CC_FOR_BUILD BUILD_CC

# late_pin NAME: NAME's SHA-256 in plumbing/late.SOURCES.
late_pin() {
  gawk -v n="$1" '$1 == n { print $2; exit }' "$ROOT/plumbing/late.SOURCES"
}

# unpack NAME ARCHIVE: verify ARCHIVE and unpack its NAME/ as OUT/src/NAME.
unpack() {
  local name=$1 archive=$distfiles/$2 want got
  want=$(late_pin "$2")
  [ -n "$want" ] || die "no pin for $2 in plumbing/late.SOURCES"
  got=$(sha "$archive")
  [ "$got" = "$want" ] || die "$archive: sha256 $got, pinned $want"
  rm -rf "$out/src/$name" "$out/src/$name.unpack"
  mkdir -p "$out/src/$name.unpack"
  case $archive in
    *.tar.gz) (cd "$out/src/$name.unpack" && gzip -dc "$archive" | tar -xf -) ;;
    *.tar.xz) (cd "$out/src/$name.unpack" && xz -dc "$archive" | tar -xf -) ;;
    *) die "unknown archive type: $archive" ;;
  esac || die "unpacking $archive failed"
  [ -d "$out/src/$name.unpack/$name" ] || die "$archive has no $name"
  mv "$out/src/$name.unpack/$name" "$out/src/$name"
  rm -rf "$out/src/$name.unpack"
}

# lrun LOG CMD...: run (chain-lib.sh), but on failure also show the end of
# LOG, since under K1 the console is all that survives a failed run.
lrun() {
  local log=$1 st
  shift
  printf '\n$ (cd %s) %s\n' "$PWD" "$*" >> "$log"
  "$@" >> "$log" 2>&1 && return 0
  st=$?
  echo "$PROG: exit $st from $1; last lines of $log:" >&2
  tail -n 25 "$log" >&2
  exit 1
}

# configure_args NAME: the arguments ladder stage 9's capture or
# ladder/stage10.sh gave NAME's configure.
configure_args() {
  case $1 in
    make-4.4.1) echo --without-guile ;;
    xz-5.6.3) echo --disable-shared --disable-threads --disable-doc ;;
    tar-1.35) echo --disable-acl --without-selinux --without-posix-acls ;;
    sed-4.9) echo --disable-acl --without-selinux ;;
    grep-3.11) echo --disable-perl-regexp ;;
    # zgrep and updatedb keep the grep and sort configure finds; name the late
    # ones (grep 2.4 lacks --label, coreutils 5.0's sort lacks -z).
    gzip-1.13) echo "GREP=$P/bin/grep" ;;
    findutils-4.10.0) echo "SORT=$P/bin/sort" ;;
    gawk-5.3.1) echo --disable-extensions --disable-mpfr --without-readline ;;
    patch-2.7.6) echo --disable-xattr ;;
    coreutils-9.5) echo --disable-acl --disable-xattr --without-selinux --without-openssl \
                        --without-gmp --disable-libcap --enable-no-install-program=stdbuf ;;
    bash-5.2.37) echo --without-bash-malloc --enable-static-link ;;
    flex-2.6.4) echo --disable-shared ;;
  esac
}

# gnu NAME ARCHIVE: patch, configure, make and install one package into P.
gnu() {
  local name=$1 archive=$2 log=$out/logs/$1.log pt t0 t1 t2 mk
  [ -e "$out/logs/$name.done" ] && return 0
  note "$name"
  rm -f "$log"
  unpack "$name" "$archive"
  for pt in "$ROOT"/patches/ladder/$name/*.diff; do
    [ -e "$pt" ] || continue
    (cd "$out/src/$name" && lrun "$log" patch -p1 -i "$pt")
  done
  # diffutils' and findutils' man/ run help2man on the built programs; like
  # stage10.sh, install the man pages as shipped and skip the regeneration.
  mk=
  case $name in diffutils-*) mk='SUBDIRS=lib src' ;; esac
  t0=$(date +%s)
  cd "$out/src/$name"
  lrun "$log" "$CONFIG_SHELL" ./configure "--build=$BUILD" "--prefix=$P" --disable-nls \
    --disable-dependency-tracking $(configure_args "$name")
  t1=$(date +%s)
  if [ -n "$mk" ]; then
    lrun "$log" make -j "$jobs" HELP2MAN=true MAKEINFO=true "$mk"
    lrun "$log" make install HELP2MAN=true MAKEINFO=true "$mk"
  else
    lrun "$log" make -j "$jobs" HELP2MAN=true MAKEINFO=true
    lrun "$log" make install HELP2MAN=true MAKEINFO=true
  fi
  t2=$(date +%s)
  cd "$out"
  echo "$name configure $((t1 - t0)) s, make $((t2 - t1)) s" > "$out/logs/$name.done"
}

started=$(date +%s)
gnu make-4.4.1 make-4.4.1.tar.gz
gnu sed-4.9 sed-4.9.tar.gz
gnu grep-3.11 grep-3.11.tar.gz
gnu gzip-1.13 gzip-1.13.tar.gz
gnu xz-5.6.3 xz-5.6.3.tar.gz
# bzip2 has no configure: its own Makefile, as stage10.sh builds it.
if [ ! -e "$out/logs/bzip2-1.0.8.done" ]; then
  note bzip2-1.0.8
  rm -f "$out/logs/bzip2-1.0.8.log"
  unpack bzip2-1.0.8 bzip2-1.0.8.tar.gz
  cd "$out/src/bzip2-1.0.8"
  lrun "$out/logs/bzip2-1.0.8.log" make "CC=$CC" "AR=$AR" "RANLIB=$RANLIB" \
    "CFLAGS=-O2 -D_FILE_OFFSET_BITS=64" LDFLAGS=-static bzip2 bzip2recover
  lrun "$out/logs/bzip2-1.0.8.log" make install "PREFIX=$P" "CC=$CC" "AR=$AR" "RANLIB=$RANLIB" \
    "CFLAGS=-O2 -D_FILE_OFFSET_BITS=64" LDFLAGS=-static
  cd "$out"
  echo "bzip2-1.0.8 make only" > "$out/logs/bzip2-1.0.8.done"
fi
gnu tar-1.35 tar-1.35.tar.gz
gnu gawk-5.3.1 gawk-5.3.1.tar.gz
gnu patch-2.7.6 patch-2.7.6.tar.gz
gnu coreutils-9.5 coreutils-9.5.tar.gz
gnu bash-5.2.37 bash-5.2.37.tar.gz
gnu diffutils-3.10 diffutils-3.10.tar.xz
gnu findutils-4.10.0 findutils-4.10.0.tar.xz
gnu m4-1.4.19 m4-1.4.19.tar.gz
gnu bison-3.8.2 bison-3.8.2.tar.gz
gnu flex-2.6.4 flex-2.6.4.tar.gz
gnu bc-1.07.1 bc-1.07.1.tar.gz

{
  echo "late tools, built by $CC"
  echo "PATH=$PATH"
  echo
  cat "$out"/logs/*.done
  echo
  echo "installed programs:"
  for f in "$P"/bin/*; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    echo "- ${f##*/}: $(sha "$f")"
  done
} > "$out/report.txt"
note "done in $(( $(date +%s) - started )) s; see $out/report.txt"
