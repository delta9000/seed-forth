#!/bin/bash
# census.sh -- compile every original GCC 4.0.4 cc1 translation unit with
# seed-cc, under the chain's own bash and make.
#
# Usage:
#   gcc-direct/census.sh WORK --oyacc OYACC --flex FLEX [-j JOBS] [--link]
#
# The bash port of census.py.  WORK holds `gcc`, `libiberty` and `libcpp`
# directories made by `configure.sh --work WORK/<component>`.  OYACC and FLEX
# are the chain's parser generators; no host bison or flex is used.
#
# The original Makefiles do the work: they decide which objects cc1 needs,
# build and run the generator programs with seed-cc, and compile each object
# with its real flags.  The only overrides are the ones configure cannot
# express: empty LDFLAGS and CFLAGS (the template hardcodes -g), the parser
# generators, and the libiberty and libcpp archive paths.  CFLAGS carries
# -Werror=implicit-function-declaration, which makes seed-cc reject any call
# to an undeclared function (census.py ran host GCC as a lint for this; under
# C90 an undeclared function returns int, which truncates a pointer result).
# `make -k` keeps going past failures, so one census reports every unit.
#
# With --link it also archives libcpp and lets the Makefile link cc1.
# Results go to WORK/census/: objects.txt, make.log, census.txt (built
# objects with SHA-256, failed objects with the compiler's error lines).  A
# successful census means the objects compiled (and, with --link, that cc1
# linked); it does not show that cc1 behaves correctly.
set -e
PROG=census
ROOT=$(cd "${0%/*}/.." && pwd)
. "$ROOT/gcc-direct/chain-lib.sh"

work= oyacc= flex= jobs=6 link=
while [ $# -gt 0 ]; do
  case $1 in
    --oyacc) oyacc=$2; shift 2 ;;
    --flex) flex=$2; shift 2 ;;
    -j|--jobs) jobs=$2; shift 2 ;;
    --link) link=1; shift ;;
    -*) die "unknown option $1" ;;
    *) work=$1; shift ;;
  esac
done
[ -n "$work" ] && [ -n "$oyacc" ] && [ -n "$flex" ] || die "usage: census.sh WORK --oyacc OYACC --flex FLEX [-j JOBS] [--link]"
work=$(absdir "$work")
oyacc=$(absfile "$oyacc") flex=$(absfile "$flex")
require_tool oyacc "$oyacc"
require_tool flex "$flex"
out=$work/census
mkdir "$out" || die "$out exists"
log=$out/make.log
: > "$log"

# census_overrides WORK OYACC FLEX: the gcc make overrides (stage-c.sh too).
libiberty=$work/libiberty/build/libiberty/libiberty.a
libcpp=$work/libcpp/build/libcpp/libcpp.a
GCC_OVERRIDES="CFLAGS=-Werror=implicit-function-declaration LDFLAGS= BISON=$oyacc FLEX=$flex LIBIBERTY=$libiberty BUILD_LIBIBERTY=$libiberty CPPLIB=$libcpp"

started=$(date +%s)
(. "$work/libiberty/configure-env.sh"
 cd "$work/libiberty/build/libiberty"
 run "$log" make -j "$jobs" CFLAGS= LDFLAGS= libiberty.a)

gcc_build=$work/gcc/build/gcc
# Ask the configured Makefile itself which objects cc1 is linked from.
printf 'print-cc1-objects:\n\t@echo $(sort $(C_OBJS) main.o $(OBJS))\n' > "$out/print-cc1-objects.mk"
objects=$(. "$work/gcc/configure-env.sh"; cd "$gcc_build" && make -s -f Makefile -f "$out/print-cc1-objects.mk" print-cc1-objects) \
  || die "could not list cc1 objects"
echo $objects | tr ' ' '\n' > "$out/objects.txt"
count=$(wc -l < "$out/objects.txt" | tr -d ' ')
note "$count cc1 objects; make log: $log"

compile_started=$(date +%s)
status=0
(. "$work/gcc/configure-env.sh"
 cd "$gcc_build"
 printf '\n$ (cd %s) make -k -j %s %s <objects>\n' "$PWD" "$jobs" "$GCC_OVERRIDES" >> "$log"
 make -k -j "$jobs" $GCC_OVERRIDES $objects >> "$log" 2>&1) || status=$?
compile_seconds=$(( $(date +%s) - compile_started ))

linked=
if [ -n "$link" ]; then
  # libcpp's 4.0.4 Makefile hardcodes `AR = ar` with `cru`; the archive is
  # removed just before, so `rc` with seed-ar is the same request.
  (. "$work/libcpp/configure-env.sh"
   cd "$work/libcpp/build/libcpp"
   run "$log" make -j "$jobs" CFLAGS= LDFLAGS= "AR=$AR" ARFLAGS=rc libcpp.a) || status=1
  (. "$work/gcc/configure-env.sh"
   cd "$gcc_build"
   run "$log" make $GCC_OVERRIDES cc1) || status=1
  if [ -f "$gcc_build/cc1" ]; then linked=1; fi
fi

built=0 failed=0
: > "$out/built.txt"
: > "$out/failed.txt"
for object in $objects; do
  if [ -f "$gcc_build/$object" ]; then
    built=$((built + 1))
    echo "$(sha "$gcc_build/$object") $object" >> "$out/built.txt"
  else
    failed=$((failed + 1))
    echo "$object" >> "$out/failed.txt"
  fi
done
{
  echo "# cc1 census: $built of $count objects compiled"
  echo
  echo "scope: compilation of original cc1 objects; no execution or bootstrap claim"
  echo "compiler: $SEED_CC ($(sha "$SEED_CC"))"
  echo "oyacc: $(sha "$oyacc")"
  echo "flex: $(sha "$flex")"
  echo "jobs: $jobs; compile seconds: $compile_seconds; total seconds: $(( $(date +%s) - started ))"
  if [ -n "$link" ]; then
    if [ -n "$linked" ]; then echo "cc1: $(sha "$gcc_build/cc1") $(wc -c < "$gcc_build/cc1" | tr -d ' ') bytes"
    else echo "cc1: not linked (see make.log)"; fi
  fi
  if [ $failed -gt 0 ]; then
    echo
    echo "Failed objects (the compiler's error lines are in make.log):"
    sed 's/^/- /' "$out/failed.txt"
    echo
    grep ' error ' "$log" | sort -u | head -50
  fi
} > "$out/census.txt"
cat "$out/census.txt"
[ $failed -eq 0 ] && { [ -z "$link" ] || [ -n "$linked" ]; } || exit 1
exit $status
