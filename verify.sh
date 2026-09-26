#!/usr/bin/env bash
# verify.sh — COMPARISONS AGAINST GCC-BUILT REFERENCES.
#
# bootstrap.sh is the GCC-free build and checks only its own fixed point.
# This script is the other half: it rebuilds GCC reference binaries
# (tests/cc/build-gcc-refs.sh: M2-Planet as m2-ref, mescc-tools' M1 and hex2)
# and shows that the GCC-free artifacts agree with them byte for byte.
#
# TRUSTS, in addition to what bootstrap.sh trusts: the host gcc (for the
# references only) and the host tools the test scripts use to compare and
# report (cmp, diff, file, timeout, wc, cp, sed, od).
#
# WHAT IT PROVES (each step is an existing script; all rebuild from scratch):
#   1. asm-light         130-asm.fth == GCC mescc-tools M1+hex2 on the small
#                        exit42 / jump42 / m1-jump42 fixtures, and the
#                        assembler's die gates (tests/asm/*-check.sh).
#   2. stage-a           Forth-built M2-Planet (cc-out-v1) emits the same
#                        amd64 .M1 as GCC-built M2-Planet on M2-Planet itself
#                        (tests/cc/stage-a-check.sh).
#   3. bootstrap-chain   per arch (x86, amd64): Stage A again, then the v2/v3
#                        self-host fixed point with bootstrap.sh's GCC-free
#                        M1/hex2, a hello-world smoke; then Stage 3: all 36
#                        M2-Planet test programs compile byte-identically
#                        with cc-out-v1 and GCC's m2-ref
#                        (tests/cc/bootstrap-chain.sh; runs bootstrap.sh).
#   4. mescc-tools       130-asm.fth assembles M2-Planet, M1 and hex2 byte-
#                        identically to GCC-built M1+hex2, and the resulting
#                        M1/hex2 behave like the GCC ones
#                        (tests/asm/m2planet-check.sh via mescc-tools-check.sh).
#   5. monolith          the bash monolith in bootstrap.sh and the sed one in
#                        tests/cc/build-m2planet-monolith.sh give the same
#                        cc-out-v1 (so Stage A covers bootstrap.sh's v1).
#
# Output: one OK/FAIL line per step, logs in $BUILDROOT/logs.
# Env: BUILDROOT (default ./build-out/verify; wiped at start),
#      PRIVATE_TMP=auto|0 — by default the whole run gets a private /tmp via
#      `unshare -rm`, because the Forth programs and the test scripts write
#      fixed /tmp paths (/tmp/cc-out, /tmp/asm-out, /tmp/m2planet-monolith.c).
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD
BUILDROOT=${BUILDROOT:-$ROOT/build-out/verify}
PRIVATE_TMP=${PRIVATE_TMP:-auto}

if [ -z "${VERIFY_IN_PRIVATE_TMP:-}" ]; then
    mkdir -p "$BUILDROOT"
    BUILDROOT=$(cd "$BUILDROOT" && pwd)
    rm -rf "$BUILDROOT"/{logs,tmp,stage-a,chain,asm,asm-light}
    mkdir -p "$BUILDROOT/tmp"
    case "$ROOT/" in /tmp/*) PRIVATE_TMP=0 ;; esac   # we'd hide our own tree
    case "$BUILDROOT/" in /tmp/*) PRIVATE_TMP=0 ;; esac
    if [ "$PRIVATE_TMP" != 0 ] && unshare -rm true 2>/dev/null; then
        export VERIFY_IN_PRIVATE_TMP=1 BUILDROOT
        exec unshare -rm bash -c 'mount --bind "$1" /tmp && exec bash "$2"' \
            _ "$BUILDROOT/tmp" "$ROOT/verify.sh"
    fi
    echo "verify: no private /tmp (unshare -rm unavailable or tree under /tmp); using the shared /tmp"
fi

command -v gcc >/dev/null || { echo "verify: gcc not on PATH — these checks compare against GCC-built references" >&2; exit 1; }

LOGS=$BUILDROOT/logs
mkdir -p "$LOGS"
T0=$SECONDS
PASS=0 FAIL=0
run() {
    local name=$1; shift
    local t=$SECONDS
    printf '%-18s' "$name ..."
    if "$@" > "$LOGS/$name.log" 2>&1; then
        echo " OK   ($((SECONDS - t))s)"; PASS=$((PASS + 1))
    else
        echo " FAIL ($((SECONDS - t))s, see $LOGS/$name.log)"; FAIL=$((FAIL + 1))
        tail -20 "$LOGS/$name.log" | sed 's/^/    | /'
    fi
}

echo "verify: comparisons against GCC-built references (BUILDROOT=$BUILDROOT)"
run 1-asm-light bash -c 'for t in exit42-check jump42-check m1-jump42-check die-gates; do
        BUILDROOT="$1/asm-light" tests/asm/$t.sh || exit 1; done' _ "$BUILDROOT"
run 2-stage-a        env BUILDROOT="$BUILDROOT/stage-a" tests/cc/stage-a-check.sh
run 3-chain          env BUILDROOT="$BUILDROOT/chain"   tests/cc/bootstrap-chain.sh
run 4-mescc-tools    env BUILDROOT="$BUILDROOT/asm"     tests/asm/mescc-tools-check.sh
run 5-monolith       cmp "$BUILDROOT/stage-a/cc-out-v1" "$BUILDROOT/chain/bootstrap/out/cc-out-v1"

echo
grep -h 'stage-a-check: self\|^A: \|^F: \|^M2-Planet tests:\|byte-identical' "$LOGS"/*.log | grep -v '^===' | sed 's/^/  /' || true
echo
if [ "$FAIL" = 0 ]; then
    echo "verify: all $PASS steps PASS in $((SECONDS - T0))s"
else
    echo "verify: $FAIL FAIL, $PASS PASS"; exit 1
fi
