#!/usr/bin/env bash
# check-all.sh — run every reproducibility check in one shot.
#
# Exit 0 iff:
#   1. ./build.sh produces a 2,040-byte seed-forth
#   2. ./test.sh passes 20/20 layer tests
#   3. tools/tangle.sh verify --strict reports 13/13 byte-identical
#   4. tools/check-numbers.py finds no drifted numeric claim in book/
#      (the prose's exact byte counts / offsets / file line counts,
#       verified against 000-seed.hex0 and the source; skipped if
#       python3 is missing)
#   5. tests/cc/stage-a-check.sh produces a byte-identical .M1
#      (skipped with a SKIP line if gcc or make is missing — only
#       Stage-A needs a host C toolchain; steps 1–4 do not)
#
# Each step's full output is captured to /tmp/check-all-NN-*.log; the
# console shows one OK/SKIP/FAIL line per step plus the final verdict.
#
# Use this before pushing, before tagging a release, and after any edit
# to a fenced code block in book/ — it is the operational form of the
# literate-program-correctness claim.

set -euo pipefail
cd "$(dirname "$0")"

LOGDIR=${TMPDIR:-/tmp}
PASS=0
SKIP=0
FAIL=0

run() {
    local name=$1; shift
    local log=$LOGDIR/check-all-$name.log
    printf '%-40s' "$name ..."
    if "$@" > "$log" 2>&1; then
        echo " OK"
        PASS=$((PASS + 1))
    else
        echo " FAIL (see $log)"
        FAIL=$((FAIL + 1))
        tail -20 "$log" | sed 's/^/    | /'
    fi
}

skip() {
    local name=$1; shift
    local reason=$1
    printf '%-40s' "$name ..."
    echo " SKIP ($reason)"
    SKIP=$((SKIP + 1))
}

run "01-build"          ./build.sh
run "02-test"           ./test.sh
run "03-tangle-strict"  tools/tangle.sh verify --strict

if command -v python3 >/dev/null 2>&1; then
    run "04-book-numbers" tools/check-numbers.py
else
    skip "04-book-numbers" "missing: python3"
fi

if command -v gcc >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
    run "05-stage-a"    tests/cc/stage-a-check.sh
else
    missing=()
    command -v gcc  >/dev/null 2>&1 || missing+=(gcc)
    command -v make >/dev/null 2>&1 || missing+=(make)
    skip "05-stage-a" "missing: ${missing[*]}"
fi

echo
if [ $FAIL -eq 0 ]; then
    if [ $SKIP -eq 0 ]; then
        echo "check-all: all $PASS steps PASS"
    else
        echo "check-all: $PASS PASS, $SKIP SKIP, 0 FAIL"
    fi
    exit 0
else
    echo "check-all: $FAIL FAIL, $PASS PASS, $SKIP SKIP"
    exit 1
fi
