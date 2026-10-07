#!/bin/bash
# configure.sh -- run an unmodified GCC 4.0.4 or binutils 2.30 configure script
# with seed-cc as the compiler, under the chain's own bash.
#
# Usage:
#   gcc-direct/configure.sh --source DIR --work WORK [--package gcc|binutils]
#       [--component gcc|libiberty|libcpp] [--forth-ar]
#       [--with-binutils DIR] [--with-sysroot DIR]
#
# The bash port of configure.py.  DIR is an unpacked source tree, prepared by
# the caller (binutils.sh and stage-c.sh unpack the pinned archives and make
# their documented adjustments); WORK may exist but must not hold a build/
# directory yet.  configure.py's per-invocation probe capture and its frozen
# copy of the compiler sources are not ported: seed-cc reads the repository's
# compiler layers, and the chain runs from a fixed source tree.
#
# Host target tools are guarded as in configure.py: WORK/guard, first in PATH,
# holds a script for each of gcc, cc, clang, as, ld, ar, ranlib, nm, ... (and
# their x86_64-pc-linux-gnu- spellings) that logs the attempt to
# WORK/host-tool-attempts.log and exits 127.  CC, CPP and CC_FOR_BUILD name
# seed-cc; AS, LD, AR, RANLIB and NM name guards.  --forth-ar makes AR seed-ar
# and RANLIB `seed-ar s`.  GCC gets --with-as/--with-ld naming the guards,
# unless --with-binutils DIR names a directory of our binutils (as and ld
# required; nm, objdump, ar and ranlib used when present): then
# --with-as=DIR/as, --with-ld=DIR/ld, each present tool's *_FOR_TARGET, and
# ./nm and ./objdump links in the gcc build directory, where GCC 4.0.4's
# configure and Makefile look first.  --with-sysroot DIR passes GCC's own
# --with-sysroot.  binutils gets CXX=no (no C++ compiler exists) and
# --disable-gold --disable-gprof --disable-plugins --disable-werror.
#
# The configure environment's recorded part goes to WORK/configure-env.sh,
# which census.sh, binutils.sh and stage-c.sh source before running make.
set -e
PROG=configure
ROOT=$(cd "${0%/*}/.." && pwd)
. "$ROOT/gcc-direct/chain-lib.sh"

package=gcc component= source= work= forth_ar= binutils= sysroot=
while [ $# -gt 0 ]; do
  case $1 in
    --package) package=$2; shift 2 ;;
    --component) component=$2; shift 2 ;;
    --source) source=$2; shift 2 ;;
    --work) work=$2; shift 2 ;;
    --forth-ar) forth_ar=1; shift ;;
    --with-binutils) binutils=$2; shift 2 ;;
    --with-sysroot) sysroot=$2; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$source" ] && [ -n "$work" ] || die "usage: configure.sh --source DIR --work WORK [options]"
case $package in
  gcc) component=${component:-gcc}
       case $component in gcc|libiberty|libcpp) ;; *) die "unknown component $component" ;; esac ;;
  binutils) [ -z "$component$binutils$sysroot" ] || die "--component, --with-binutils and --with-sysroot apply to gcc only"
       component=top ;;
  *) die "unknown package $package" ;;
esac
source=$(absdir "$source")
if [ -n "$sysroot" ]; then
  sysroot=$(absdir "$sysroot")
  [ -d "$sysroot/usr/include" ] || die "--with-sysroot needs target headers in $sysroot/usr/include"
fi
if [ -n "$binutils" ]; then
  binutils=$(absdir "$binutils")
  for tool in as ld; do
    [ -f "$binutils/$tool" ] && [ -x "$binutils/$tool" ] || die "--with-binutils needs an executable $binutils/$tool"
  done
fi
mkdir -p "$work"
work=$(absdir "$work")
[ -e "$work/build" ] && die "$work/build exists"
build=$work/build/$component
mkdir -p "$build" "$work/guard"

# Guards: any use of a host compiler or target tool is logged and fails.
for name in gcc cc clang clang++ g++ c++ tcc cpp as ld ar ranlib nm strip objcopy gcj gfortran; do
  for spelling in $name $TRIPLE-$name; do
    printf '#!%s\necho "$0 $*" >> %s/host-tool-attempts.log\necho "direct-gcc: host target tool blocked: %s" >&2\nexit 127\n' \
      "$BASH" "$work" "$spelling" > "$work/guard/$spelling"
    chmod 755 "$work/guard/$spelling"
  done
done

# No cached configure answer may leak in from the caller's environment.
for name in $(env | sed -n 's/^\([A-Za-z_][A-Za-z_0-9]*\)=.*/\1/p'); do
  case $name in
    *_cv_*|ac_cv*|gcc_cv*|gt_cv*) unset "$name" ;;
  esac
done

G=$work/guard
PATH=$G:$PATH
CONFIG_SITE=/dev/null CONFIG_SHELL=$BASH
CC=$SEED_CC CPP="$SEED_CC -E" CC_FOR_BUILD=$SEED_CC
CXX=$G/c++ CXXCPP=$G/cpp
CFLAGS= CPPFLAGS= LDFLAGS= LIBS= CFLAGS_FOR_BUILD= CXXFLAGS=
AS=$G/as LD=$G/ld AR=$G/ar RANLIB=$G/ranlib NM=$G/nm
AS_FOR_TARGET=$G/as LD_FOR_TARGET=$G/ld
export PATH CONFIG_SITE CONFIG_SHELL CC CPP CC_FOR_BUILD CXX CXXCPP CFLAGS CPPFLAGS LDFLAGS LIBS
export CFLAGS_FOR_BUILD CXXFLAGS AS LD AR RANLIB NM AS_FOR_TARGET LD_FOR_TARGET
if [ $package = binutils ]; then CXX=no; fi
if [ -n "$forth_ar" ]; then AR=$SEED_AR RANLIB="$SEED_AR s"; fi
target_as=$G/as target_ld=$G/ld
if [ -n "$binutils" ]; then
  target_as=$binutils/as target_ld=$binutils/ld
  AS_FOR_TARGET=$target_as LD_FOR_TARGET=$target_ld
  for tool in nm objdump ar ranlib; do
    if [ -f "$binutils/$tool" ] && [ -x "$binutils/$tool" ]; then
      case $tool in
        nm) NM_FOR_TARGET=$binutils/nm; export NM_FOR_TARGET ;;
        objdump) OBJDUMP_FOR_TARGET=$binutils/objdump; export OBJDUMP_FOR_TARGET ;;
        ar) AR_FOR_TARGET=$binutils/ar; export AR_FOR_TARGET ;;
        ranlib) RANLIB_FOR_TARGET=$binutils/ranlib; export RANLIB_FOR_TARGET ;;
      esac
      # gcc/configure takes `test -x nm` / `test -x objdump` in its build
      # directory first; the Makefile's NM_FOR_TARGET likewise prefers ./nm.
      if [ $component = gcc ] && { [ $tool = nm ] || [ $tool = objdump ]; }; then
        ln -s "$binutils/$tool" "$build/$tool"
      fi
    fi
  done
fi

# The part of the environment later make runs need, as configure.py records it.
: > "$work/configure-env.sh"
for name in CC CPP CXX CXXCPP CC_FOR_BUILD CFLAGS CPPFLAGS LDFLAGS LIBS CONFIG_SITE CONFIG_SHELL \
            PATH AS LD AR RANLIB NM; do
  eval "value=\$$name"
  printf "%s='%s'\nexport %s\n" "$name" "$value" "$name" >> "$work/configure-env.sh"
done

if [ $component = top ]; then configure=$source/configure; else configure=$source/$component/configure; fi
set -- --build=$TRIPLE --host=$TRIPLE --target=$TRIPLE --prefix=$work/install \
  --disable-shared --disable-nls --disable-multilib --enable-languages=c \
  --cache-file=/dev/null --with-as=$target_as --with-ld=$target_ld --program-transform-name=
if [ $package = binutils ]; then
  set -- "$@" --disable-gold --disable-gprof --disable-plugins --disable-werror
fi
if [ -n "$sysroot" ]; then set -- "$@" --with-sysroot=$sysroot; fi
echo "$BASH $configure $*" > "$work/configure-command.txt"
echo "$work"
status=0
(cd "$build" && "$BASH" "$configure" "$@") > "$work/configure.log" 2>&1 || status=$?
attempts=0
if [ -f "$work/host-tool-attempts.log" ]; then attempts=$(wc -l < "$work/host-tool-attempts.log"); fi
cat > "$work/report.txt" <<EOF
configuration: provisional; probe and generated-header audit required
package: $package
component: $component
returncode: $status
source: $source
compiler: $SEED_CC ($(sha "$SEED_CC"))
target_as: $target_as
target_ld: $target_ld
sysroot: ${sysroot:-none}
archive_adapter: $([ -n "$forth_ar" ] && echo "seed-ar" || echo "guarded, unavailable")
host_tool_attempts: $attempts
EOF
cat "$work/report.txt"
exit $status
