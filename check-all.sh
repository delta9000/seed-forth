#!/usr/bin/env bash
# check-all.sh — run every reproducibility check in one shot.
#
# Exit 0 iff:
#   1.  ./build.sh produces a 1,772-byte seed-forth
#   2.  ./test.sh passes all its seed and layer tests
#   2a. the four light tests/asm checks (exit42, jump42, m1-jump42, and
#       die-gates, the assembler's error codes); the heavyweight
#       m2planet/mescc-tools checks stay opt-in in ./verify.sh
#       (skipped if gcc is missing — these tests compare against GCC-built
#        mescc-tools, rebuilt fresh by tests/cc/build-gcc-refs.sh)
#   2b. tests/cc/run-gates.sh all registered C gates pass
#   3.  tools/tangle.sh verify --strict reports 13/13 byte-identical
#   4.  tools/check-numbers.py finds no drifted numeric claim in book/
#       (the prose's exact byte counts / offsets / file line counts,
#        verified against 000-seed.hex0 and the source; skipped if
#        python3 is missing)
#   4a. tools/check-tryit.py runs every ```sh "Try it" block in book/
#       that pipes into ./seed-forth (in a scratch dir with a private
#       /tmp) and checks it runs cleanly, leaves no stray files, and
#       prints the output the book states (skipped if python3 is missing)
#   4b. tools/gen-index.py --check: the committed book/WORD-INDEX.md matches what
#       the chapters' fences and headings generate (skipped if python3 is
#       missing)
#   4c. tools/check-links.py: every relative link in book/*.md resolves, every
#       #anchor matches a heading id by mdBook's slug rules, and no rendered
#       chapter links outside book/ (skipped if python3 is missing)
#   5.  tests/cc/stage-a-check.sh produces a byte-identical .M1
#       (skipped with a SKIP line if gcc is missing — only 2a and 5 need a
#        host C compiler, and only to build the references they compare to)
#   6.  ./bootstrap.sh, the GCC-free build: hex0-seed -> seed-forth ->
#       M2-Planet -> M1 + hex2 (via 130-asm.fth) -> M2-Planet v2 -> v3, with
#       the v2 == v3 self-host fixed point (~30 s; output in ./build-out/out).
#       Needs no gcc, so it is never skipped.
#   7.  ./handoff.sh route A on step 6's output (ARCHES=amd64 ROUTE_B=0,
#       ~20 s): stage0-posix's own recipe from Phase 6 on, fed by the Forth
#       route in place of hex1/hex2/M0/cc_amd64, reproduces all 19
#       amd64.answers binaries.  SKIP when vendor/stage0-posix's nested
#       submodules are not checked out (handoff.sh exits 77).  ./verify.sh
#       runs the full handoff.sh (route B, and the x86 hand-off, ~4 min).
#
# Not here, because they are slow and repeat what 5 and 6 cover: the per-arch
# chain, M2-Planet test-suite parity and the mescc-tools byte-identity checks.
# Run ./verify.sh for those (all comparisons against GCC-built references).
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

if command -v gcc >/dev/null 2>&1; then
    run "02a-asm"           bash -c 'for t in tests/asm/exit42-check.sh tests/asm/jump42-check.sh tests/asm/m1-jump42-check.sh tests/asm/die-gates.sh; do "$t" || exit 1; done'
else
    skip "02a-asm" "missing: gcc"
fi

run "02b-gates"         tests/cc/run-gates.sh
run "03-tangle-strict"  tools/tangle.sh verify --strict

if command -v python3 >/dev/null 2>&1; then
    run "04-book-numbers" tools/check-numbers.py
else
    skip "04-book-numbers" "missing: python3"
fi

if command -v python3 >/dev/null 2>&1; then
    run "04a-tryit"       tools/check-tryit.py --verbose
else
    skip "04a-tryit" "missing: python3"
fi

if command -v python3 >/dev/null 2>&1; then
    run "04b-index"       tools/gen-index.py --check
else
    skip "04b-index" "missing: python3"
fi

if command -v python3 >/dev/null 2>&1; then
    run "04c-links"       tools/check-links.py
else
    skip "04c-links" "missing: python3"
fi

if command -v gcc >/dev/null 2>&1; then
    run "05-stage-a"    tests/cc/stage-a-check.sh
else
    skip "05-stage-a" "missing: gcc"
fi

run "06-bootstrap"      ./bootstrap.sh

# 07: handoff.sh exits 77 when stage0-posix's nested submodules are missing.
printf '%-40s' "07-handoff ..."
rc=0
BOOTSTRAP_OUT=build-out/out ARCHES=amd64 ROUTE_B=0 ./handoff.sh > "$LOGDIR/check-all-07-handoff.log" 2>&1 || rc=$?
if [ $rc -eq 0 ]; then
    echo " OK"; PASS=$((PASS + 1))
elif [ $rc -eq 77 ]; then
    echo " SKIP ($(grep -m1 'SKIP' "$LOGDIR/check-all-07-handoff.log" | sed 's/^handoff: SKIP: //'))"
    SKIP=$((SKIP + 1))
else
    echo " FAIL (see $LOGDIR/check-all-07-handoff.log)"; FAIL=$((FAIL + 1))
    tail -20 "$LOGDIR/check-all-07-handoff.log" | sed 's/^/    | /'
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
