#!/bin/bash
# stage-d.sh -- stage D: GCC 4.0.4 rebuilds itself from the seed-built
# compiler to a fixed point.
#
# Usage:
#   gcc-direct/stage-d.sh WORK --stage-c STAGE_C_WORK --oyacc OYACC \
#       --flex FLEX [-j JOBS]
#
# The bash port of stage-d.py, run by the chain's own bash and make.
# STAGE_C_WORK is a finished stage-c.sh run: its installed GCC (whose cc1 and
# driver seed-cc compiled), its musl sysroot and its binutils (toolchain/).
# GCC 4.0.4 (C only) is then built three times, as gcc64/build-gcc4.sh does
# (libiberty, libcpp and gcc configured one by one, no fixincludes), each
# time with the previous generation as the compiler:
#
#   stage 2  built by the stage-C GCC   installed at WORK/prefix
#   stage 3  built by stage 2           installed with DESTDIR=WORK/stage3
#   stage 4  built by stage 3           installed with DESTDIR=WORK/stage4
#
# Every build uses the same source path, build path and prefix, so the paths
# compiled into the binaries agree.  The pass criterion is a fixed point
# reached at once: stages 2, 3 and 4 must install the same files with the
# same bytes.  Archives are compared member by member (names, order and
# member bytes), because binutils 2.30 `ar` stores member timestamps.  Stage 2
# can match only because the runtime's qsort is musl's (see stage-d.py and
# runtime/gcc-seed/SORT.md).
#
# Source adaptation, applied to a fresh unpacking of the pinned tar: gcc's
# system.h exempts parser-generator code (FLEX_SCANNER, YYBISON) from its
# malloc/realloc poisoning but not Berkeley yacc's YYBYACC, which the chain's
# oyacc defines; the exemption is made to match.  The collect2 patch in
# patches/gcc64/gcc-4.0.4/ is applied as in gcc64/build-gcc4.sh.  The front
# ends and libraries other than C are removed.  Each stage's configure,
# make and install output goes to WORK/stageN.log; the result is in
# WORK/report.txt.  The stage-C cc1 runs with a 64 MiB stack: seed-cc's
# frames are larger than GCC's and some GCC sources recurse deeply.
set -e
PROG=stage-d
ROOT=$(cd "${0%/*}/.." && pwd)
. "$ROOT/gcc-direct/chain-lib.sh"

SKIP="libjava gcc/testsuite libgfortran libstdc++-v3 libada gcc/ada boehm-gc libffi gcc/java
  gcc/fortran gcc/cp gcc/objc gcc/objcp gcc/treelang libobjc"
POISON_OLD='#if !defined(FLEX_SCANNER) && !defined(YYBISON)'
POISON_NEW='#if !defined(FLEX_SCANNER) && !defined(YYBISON) && !defined(YYBYACC)'

work= stage_c= oyacc= flex= jobs=8
while [ $# -gt 0 ]; do
  case $1 in
    --stage-c) stage_c=$2; shift 2 ;;
    --oyacc) oyacc=$2; shift 2 ;;
    --flex) flex=$2; shift 2 ;;
    -j|--jobs) jobs=$2; shift 2 ;;
    -*) die "unknown option $1" ;;
    *) work=$1; shift ;;
  esac
done
[ -n "$work" ] && [ -n "$stage_c" ] && [ -n "$oyacc" ] && [ -n "$flex" ] \
  || die "usage: stage-d.sh WORK --stage-c STAGE_C_WORK --oyacc OYACC --flex FLEX [-j JOBS]"
stage_c=$(absdir "$stage_c") oyacc=$(absfile "$oyacc") flex=$(absfile "$flex")
require_tool oyacc "$oyacc"
require_tool flex "$flex"
[ -e "$work" ] && die "$work exists"
mkdir -p "$work"
work=$(absdir "$work")
ulimit -S -s 65536 || die "cannot raise the stack limit to 64 MiB"
prefix=$work/prefix
sysroot=$stage_c/sysroot
tools=$stage_c/toolchain
source=$work/src/gcc-4.0.4-work

# extract: a fresh C-only GCC tree with the documented adaptations.
extract() {
  local dir patch n
  rm -rf "$source"
  mkdir -p "$work/src"
  untar "$GCC_TAR" "$source" gcc-4.0.4
  for dir in $SKIP; do rm -rf "$source/$dir"; done
  n=$(grep -cxF "$POISON_OLD" "$source/gcc/system.h" || true)
  [ "$n" = 1 ] || die "unexpected gcc/system.h: poison exemption line not found exactly once"
  gawk -v old="$POISON_OLD" -v new="$POISON_NEW" '$0 == old { print new; next } { print }' \
    "$source/gcc/system.h" > "$source/gcc/system.h.new"
  mv "$source/gcc/system.h.new" "$source/gcc/system.h"
  for patch in "$ROOT"/patches/gcc64/gcc-4.0.4/*.diff; do
    (cd "$source" && patch -s -p1 -F0 -i "$patch") || die "patch $patch failed"
  done
}

# build NAME COMPILER [DESTDIR]: configure, build and install one generation.
build() {
  local name=$1 compiler=$2 destdir=$3 log=$work/$1.log started component installed
  started=$(date +%s)
  : > "$log"
  extract
  # The stage-C binutils come first in PATH: gcc/configure looks for nm and
  # objdump there for its .subsection, eh_frame and section-mixing probes.
  # Without them those probes fail and stages 3 and 4 get crt objects built
  # under different answers from the stage-C ones stage 2 links with.
  (PATH=$tools:$PATH
   CC=$compiler CPP="$compiler -E" CFLAGS=-O2 LDFLAGS=-static AR=$tools/ar RANLIB=$tools/ranlib
   BISON=$oyacc YACC=$oyacc FLEX=$flex LEX=$flex CONFIG_SHELL=$BASH
   export PATH CC CPP CFLAGS LDFLAGS AR RANLIB BISON YACC FLEX LEX CONFIG_SHELL
   for component in libiberty libcpp gcc; do
     mkdir -p "$source/build/$component"
     (cd "$source/build/$component" && run "$log" "$BASH" ../../$component/configure "--prefix=$prefix" \
        "--build=$TRIPLE" "--host=$TRIPLE" "--target=$TRIPLE" --disable-shared --disable-nls \
        --disable-multilib --enable-languages=c "--with-sysroot=$sysroot" "--with-as=$tools/as" \
        "--with-ld=$tools/ld" --program-transform-name=)
   done
   ln -s . "$source/build/build-$TRIPLE"
   mkdir "$source/build/gcc/include"
   ln -s ../../../gcc/gsyslimits.h "$source/build/gcc/include/syslimits.h"
   sed 's/^STMP_FIXINC = stmp-fixinc$/STMP_FIXINC =/' "$source/build/gcc/Makefile" > "$source/build/gcc/Makefile.new"
   mv "$source/build/gcc/Makefile.new" "$source/build/gcc/Makefile"
   overrides="CFLAGS=-O2 LDFLAGS=-static LIBGCC2_INCLUDES=-I$sysroot/usr/include BISON=$oyacc YACC=$oyacc FLEX=$flex LEX=$flex MAKEINFO=true AR=$tools/ar RANLIB=$tools/ranlib"
   for component in libiberty libcpp gcc; do
     (cd "$source/build/$component" && run "$log" make -j "$jobs" $overrides)
   done
   if [ -n "$destdir" ]; then installed=$destdir$prefix; else installed=$prefix; fi
   mkdir -p "$installed/lib/gcc/$TRIPLE/4.0.4/install-tools/include"
   if [ -n "$destdir" ]; then
     (cd "$source/build/gcc" && run "$log" make install MAKEINFO=true "DESTDIR=$destdir")
   else
     (cd "$source/build/gcc" && run "$log" make install MAKEINFO=true)
   fi
   rm -f "$installed/lib/gcc/$TRIPLE/4.0.4/include/syslimits.h"
   cp "$source/gcc/gsyslimits.h" "$installed/lib/gcc/$TRIPLE/4.0.4/include/syslimits.h")
  echo "$name: $(( $(date +%s) - started )) s, built by $compiler" >> "$work/steps.txt"
  note "$name built in $(( $(date +%s) - started )) s"
}

# same_archive A B: the archives hold the same members, in order, with the
# same bytes.
same_archive() {
  local member
  "$tools/ar" t "$1" > "$work/cmp.a.list" && "$tools/ar" t "$2" > "$work/cmp.b.list" || return 1
  cmp -s "$work/cmp.a.list" "$work/cmp.b.list" || return 1
  for member in $(cat "$work/cmp.a.list"); do
    "$tools/ar" p "$1" "$member" > "$work/cmp.a.member"
    "$tools/ar" p "$2" "$member" > "$work/cmp.b.member"
    cmp -s "$work/cmp.a.member" "$work/cmp.b.member" || return 1
  done
}

# compare A B LABEL: write LABEL.txt (counts, files only in one tree, files
# that differ) and print its summary line; status 0 when the trees agree.
compare() {
  local a=$1 b=$2 label=$3 name differ=0 total
  files "$a" | sort > "$work/$label.first"
  files "$b" | sort > "$work/$label.second"
  total=$(wc -l < "$work/$label.first" | tr -d ' ')
  : > "$work/$label.differ"
  for name in $(comm -12 "$work/$label.first" "$work/$label.second"); do
    cmp -s "$a/$name" "$b/$name" && continue
    case $name in *.a) same_archive "$a/$name" "$b/$name" && continue ;; esac
    echo "$name" >> "$work/$label.differ"
  done
  {
    echo "files: $total"
    echo "only in first: $(comm -23 "$work/$label.first" "$work/$label.second" | tr '\n' ' ')"
    echo "only in second: $(comm -13 "$work/$label.first" "$work/$label.second" | tr '\n' ' ')"
    echo "differing: $(tr '\n' ' ' < "$work/$label.differ")"
  } > "$work/$label.txt"
  differ=$(wc -l < "$work/$label.differ" | tr -d ' ')
  echo "$total files, $differ differ$( [ $differ -gt 0 ] && echo " ($(tr '\n' ' ' < "$work/$label.differ"))")"
  [ $differ -eq 0 ] && cmp -s "$work/$label.first" "$work/$label.second"
}

: > "$work/steps.txt"
build stage2 "$stage_c/gcc/install/bin/gcc"
build stage3 "$prefix/bin/gcc" "$work/stage3"
stage3=$work/stage3$prefix
build stage4 "$stage3/bin/gcc" "$work/stage4"
stage4=$work/stage4$prefix

passed=yes
fixed=$(compare "$stage3" "$stage4" stage3-vs-stage4) || passed=
second=$(compare "$prefix" "$stage3" stage2-vs-stage3) || passed=
{
  if [ -n "$passed" ]; then echo "# Stage D: fixed point reached"; else echo "# Stage D: NO fixed point"; fi
  echo
  echo "Stage 3 vs stage 4: $fixed."
  echo "Stage 2 vs stage 3: $second."
  echo
  sed 's/^/- /' "$work/steps.txt"
  echo
  for name in bin/gcc libexec/gcc/$TRIPLE/4.0.4/cc1 libexec/gcc/$TRIPLE/4.0.4/collect2; do
    echo "- $name: $(sha "$stage4/$name")"
  done
} > "$work/report.txt"
cat "$work/report.txt"
[ -n "$passed" ]
