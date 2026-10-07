#!/bin/bash
# chain.sh -- from the plumbing tools to the GCC 4.0.4 fixed point.
#
# Usage (from the repository root, after plumbing/stage1.kaem, stage2.kaem,
# lexers.kaem and bash.kaem):
#   build-out/plumbing/bin/bash gcc-direct/chain.sh [-j JOBS] [OUT]
#
# Runs binutils.sh, stage-c.sh and stage-d.sh in order with the chain's
# oyacc and flex, into OUT (default build-out/chain): OUT/binutils,
# OUT/stage-c and OUT/stage-d.  PATH is set to build-out/plumbing/bin alone,
# so every program these scripts start is one the plumbing stages built (or
# one the chain builds on the way: binutils, GCC, the guards).  A finished
# OUT/binutils is kept and an existing OUT/stage-c is resumed; OUT/stage-d
# must not exist yet.
set -e
PROG=chain
ROOT=$(cd "${0%/*}/.." && pwd)
. "$ROOT/gcc-direct/chain-lib.sh"

jobs=6 out=
while [ $# -gt 0 ]; do
  case $1 in
    -j|--jobs) jobs=$2; shift 2 ;;
    -*) die "unknown option $1" ;;
    *) out=$1; shift ;;
  esac
done
BIN=$ROOT/build-out/plumbing/bin
PATH=$BIN
export PATH
out=${out:-$ROOT/build-out/chain}
mkdir -p "$out"
out=$(absdir "$out")
started=$(date +%s)
if grep -qx 'built: 6 of 6' "$out/binutils/stage-b/report.txt" 2>/dev/null; then
  note "binutils: already built in $out/binutils"
else
  note "binutils"
  "$BASH" "$ROOT/gcc-direct/binutils.sh" "$out/binutils" --oyacc "$BIN/oyacc" --flex "$BIN/flex" -j "$jobs"
fi
note "stage C"
"$BASH" "$ROOT/gcc-direct/stage-c.sh" "$out/stage-c" --binutils "$out/binutils" \
  --oyacc "$BIN/oyacc" --flex "$BIN/flex" -j "$jobs" --resume
note "stage D"
"$BASH" "$ROOT/gcc-direct/stage-d.sh" "$out/stage-d" --stage-c "$out/stage-c" \
  --oyacc "$BIN/oyacc" --flex "$BIN/flex" -j "$jobs"
note "done in $(( $(date +%s) - started )) s"
