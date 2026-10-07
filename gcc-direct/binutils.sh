#!/bin/bash
# binutils.sh -- build original binutils 2.30 (stage B) with seed-cc, under
# the chain's own bash and make.
#
# Usage:
#   gcc-direct/binutils.sh WORK --oyacc OYACC --flex FLEX [-j JOBS]
#
# The bash port of binutils.py.  WORK must be new.  The pinned
# binutils-2.30.tar (plumbing/chain.SOURCES) is unpacked into WORK/src, and
# the parser and scanner C shipped in the release is deleted, so that the
# original Makefiles must regenerate it from the .y and .l sources with the
# chain's oyacc and flex; hand-written ldlex.h, itbl-lex.h and m68k-parse.h
# stay.  configure.sh --package binutils --forth-ar configures the top level.
#
# make runs from WORK/build/top with WORK/configure-env.sh.  Empty CFLAGS and
# LDFLAGS avoid the templates' debug, optimization and host-link flags.  Empty
# WARN_CFLAGS and WARN_WRITE_STRINGS drop GCC-only warnings: bfd/warning.m4
# takes any __GNUC__ that is not 0-3 for GCC 4+ and adds -Wwrite-strings,
# which seed-cc rejects by design.  YACC/BISON both name OYACC and LEX/FLEX
# both name FLEX, covering every spelling the Makefiles use.  `make -k` builds
# all-gas, all-ld and all-binutils; then gas, ld and binutils are made
# directly, because the top level's MAKEOVERRIDES= drops the WARN_ overrides
# on the way down.  Only those three direct makes, not the top-level one,
# must succeed.
#
# WORK/stage-b/report.txt lists each tool, built or not, with its SHA-256;
# stage-c.sh checks the tools it takes against it.  Built executables are not
# an execution or bootstrap proof.
set -e
PROG=binutils
ROOT=$(cd "${0%/*}/.." && pwd)
. "$ROOT/gcc-direct/chain-lib.sh"

TOOLS="gas/as-new ld/ld-new binutils/ar binutils/nm-new binutils/objdump binutils/readelf"
# Shipped generated parser/scanner C and headers (configure.py's list).
GENERATED="binutils/arlex.c binutils/arparse.c binutils/arparse.h
  binutils/deflex.c binutils/defparse.c binutils/defparse.h
  binutils/mcparse.c binutils/mcparse.h binutils/nlmheader.c
  binutils/nlmheader.h binutils/rcparse.c binutils/rcparse.h
  binutils/sysinfo.c binutils/sysinfo.h binutils/syslex.c
  gas/itbl-lex.c gas/itbl-parse.c gas/itbl-parse.h
  intl/plural.c ld/deffilep.c ld/deffilep.h
  ld/ldgram.c ld/ldgram.h ld/ldlex.c"

work= oyacc= flex= jobs=6
while [ $# -gt 0 ]; do
  case $1 in
    --oyacc) oyacc=$2; shift 2 ;;
    --flex) flex=$2; shift 2 ;;
    -j|--jobs) jobs=$2; shift 2 ;;
    -*) die "unknown option $1" ;;
    *) work=$1; shift ;;
  esac
done
[ -n "$work" ] && [ -n "$oyacc" ] && [ -n "$flex" ] || die "usage: binutils.sh WORK --oyacc OYACC --flex FLEX [-j JOBS]"
[ "$jobs" -ge 1 ] || die "jobs must be at least 1"
oyacc=$(absfile "$oyacc") flex=$(absfile "$flex")
require_tool oyacc "$oyacc"
require_tool flex "$flex"
[ -e "$work" ] && die "work directory already exists: $work"
mkdir -p "$work/src"
work=$(absdir "$work")

note "unpacking $BINUTILS_TAR"
source=$work/src/binutils-2.30
untar "$BINUTILS_TAR" "$source" binutils-2.30
: > "$work/generated-removed.txt"
for name in $GENERATED; do
  [ -f "$source/$name" ] || die "listed generated file is absent: $name"
  echo "$(sha "$source/$name") $name" >> "$work/generated-removed.txt"
  rm "$source/$name"
done

note "configuring: $work"
status=0
"$BASH" "$ROOT/gcc-direct/configure.sh" --package binutils --forth-ar --source "$source" --work "$work" \
  > "$work.configure.out" 2>&1 || status=$?
note "configure exit $status"
steps="configure $status"
if [ $status -eq 0 ]; then
  . "$work/configure-env.sh"
  overrides="CFLAGS= LDFLAGS= WARN_CFLAGS= WARN_WRITE_STRINGS= YACC=$oyacc BISON=$oyacc LEX=$flex FLEX=$flex"
  note "building with $jobs jobs; log: $work/make.log"
  status=0
  (cd "$work/build/top" && make -k -j "$jobs" $overrides all-gas all-ld all-binutils) > "$work/make.log" 2>&1 || status=$?
  note "make exit $status"
  steps="$steps; make $status"
  for directory in gas ld binutils; do
    if [ ! -f "$work/build/top/$directory/Makefile" ]; then
      note "$directory not configured; skipped"
      steps="$steps; make-$directory skipped"
      continue
    fi
    status=0
    (cd "$work/build/top/$directory" && make -k -j "$jobs" $overrides) > "$work/make-$directory.log" 2>&1 || status=$?
    note "make $directory exit $status"
    steps="$steps; make-$directory $status"
  done
fi

mkdir "$work/stage-b"
built=0 total=0 ok=1
{
  echo "scope: original binutils stage-B build; configure answers provisional; no execution or bootstrap claim"
  echo "compiler: $SEED_CC ($(sha "$SEED_CC"))"
  echo "binutils_archive: $(pinned binutils-2.30.tar)"
  echo "oyacc: $(sha "$oyacc")"
  echo "flex: $(sha "$flex")"
  echo "jobs: $jobs"
  echo "steps: $steps"
} > "$work/stage-b/report.txt"
for tool in $TOOLS; do
  total=$((total + 1))
  if [ -f "$work/build/top/$tool" ] && [ -x "$work/build/top/$tool" ]; then
    built=$((built + 1))
    echo "tool: $tool $(sha "$work/build/top/$tool")" >> "$work/stage-b/report.txt"
  else
    ok=
    echo "tool: $tool not-built" >> "$work/stage-b/report.txt"
  fi
done
# The top-level make is expected to fail (the WARN_ overrides never reach the
# tool directories); the configure and per-directory makes must succeed.
case "${steps%%;*}; ${steps#*; make [0-9]*; }" in *" "[1-9]*|*skipped*) ok= ;; esac
echo "built: $built of $total" >> "$work/stage-b/report.txt"
cat "$work/stage-b/report.txt"
[ -n "$ok" ]
