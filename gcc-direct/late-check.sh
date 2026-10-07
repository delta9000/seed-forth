#!/bin/bash
# late-check.sh -- run each late tool's own test suite (make check).
#
# Usage, after gcc-direct/late-tools.sh:
#   bash gcc-direct/late-check.sh [-j JOBS] [OUT]     (OUT default build-out/late)
#
# The late tools come first in PATH here (bash 5.2 is the shell, also as
# make's SHELL and CONFIG_SHELL, which configure set to the plumbing bash or
# /bin/sh; make 4.4.1
# runs the suites), with build-out/plumbing/bin and the stage-C binutils after
# them.  Each package's results go to OUT/logs/NAME.check and a summary line
# per package to OUT/check.txt.  A failing suite does not stop the others.
PROG=late-check
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
out=$(absdir "${out:-$ROOT/build-out/late}")
P=$out/usr
PATH=$P/bin:$ROOT/build-out/plumbing/bin:$ROOT/build-out/chain/stage-c/toolchain
CONFIG_SHELL=$P/bin/bash SHELL=$P/bin/bash HOME=$out TZ=UTC0
unset _POSIX2_VERSION
export PATH CONFIG_SHELL SHELL HOME TZ

: > "$out/check.txt"
for dir in "$out"/src/*/; do
  name=${dir%/}
  name=${name##*/}
  case $name in bzip2-*|*.unpack) continue ;; esac
  note "$name"
  (cd "$dir" && make -k -j "$jobs" check "SHELL=$SHELL" "CONFIG_SHELL=$SHELL" HELP2MAN=true MAKEINFO=true) > "$out/logs/$name.check" 2>&1
  status=$?
  # automake's parallel harness prints "# PASS:  N" lines, one block per suite.
  summary=$(grep -E '^# (PASS|FAIL|SKIP|XFAIL|ERROR): ' "$out/logs/$name.check" |
    awk '{ n[$2] += $3 } END { for (k in n) printf "%s %d ", k, n[k] }')
  failed=$(grep -E '^(FAIL|ERROR): ' "$out/logs/$name.check" | sort -u | tr '\n' ' ')
  echo "$name: make exit $status; $summary$failed" >> "$out/check.txt"
done
cat "$out/check.txt"
