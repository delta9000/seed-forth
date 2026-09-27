#!/usr/bin/env bash
# verify.sh — COMPARISONS AGAINST GCC-BUILT REFERENCES (steps 1-5) and
# against stage0-posix (steps 6-7).
#
# bootstrap.sh is the GCC-free build and checks only its own fixed point.
# This script is the other half: it rebuilds GCC reference binaries
# (tests/cc/build-gcc-refs.sh: M2-Planet as m2-ref, mescc-tools' M1 and hex2)
# and shows that the GCC-free artifacts agree with them byte for byte.
#
# Steps 6-7 then compare the Forth route with the canonical stage0-posix
# route and hand it over to stage0-posix's own recipe.
#
# TRUSTS, in addition to what bootstrap.sh trusts: the host gcc (for the
# references only) and the host tools the test scripts use to compare and
# report (cmp, diff, file, timeout, wc, cp, sed, od).  Steps 6-7 trust the
# vendor/stage0-posix sources at its pins; step 6 also runs stage0-posix's
# kaem-optional-seed and the chain it builds.  Their headers are exact.
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
# Then two cross-checks against stage0-posix instead of GCC (no gcc used;
# each SKIPs, exit 77, when vendor/stage0-posix's nested submodules
# M2-Planet, M2libc, mescc-tools, mescc-tools-extra, M2-Mesoplanet are not
# checked out; see the Prerequisite note in either script):
#   6. stage0            tests/cc/stage0-check.sh: stage0-posix's own AMD64
#                        chain reproduces amd64.answers, and the Forth-rooted
#                        and stage0-rooted chains reach the same M2-Planet
#                        0a67a68 binary one generation after cc-out-v1 (DDC),
#                        also when each side links only with its own
#                        M1/hex2/blood-elf (stage 4b, on step 3's
#                        bootstrap.sh output).
#   7. handoff           ./handoff.sh on step 3's bootstrap.sh output: stage0's
#                        AMD64 and x86 recipes from Phase 6 on, fed by the
#                        Forth route instead of hex1/hex2/M0/cc_amd64/cc_x86,
#                        reproduce all 19 amd64.answers and all 19
#                        x86.answers binaries (x86 needs the kernel's IA-32
#                        emulation; SKIP without it or without
#                        vendor/stage0-posix/x86).
#
# And one long GCC-free run that check-all.sh does only in part:
#   8. pnut              tests/pnut/sf-pnut-check.sh with SF_PNUT_TCC=1: the
#                        Forth C compiler builds pnut (vendor/pnut)
#                        unmodified; that pnut and an M2-Planet-built one
#                        (step 3's cc-out-v3/M1/hex2) build the same
#                        pnut-exe, and pnut's own TCC kit carries it on to
#                        tcc-0.9.27 with pnut's published tcc-boot2 =
#                        tcc-boot3 hash (~2 min; SKIP without vendor/pnut).
#
# And one more REFERENCE COMPARISON against gcc, on the amd64 route:
#   9. pnut-amd64        tests/pnut/sf-pnut-amd64-check.sh with
#                        SF_PNUT64_GCC_ORACLE=1: the GCC-free amd64 chain
#                        (seed-forth -> SF-built pnut -> tcc-0.9.27 x86_64,
#                        tcc-boot2 = tcc-boot3, every hash pinned; the same
#                        run as check-all.sh's 06b), then the reference: a
#                        gcc-built pnut builds the same pnut64-g2 and
#                        pnut-exe, and a gcc-built tcc-0.9.27 (same patched
#                        sources and -D flags as tcc-pnut) seeds the same
#                        tcc-boot2 and boot2 crt1.o/libc.a/libtcc1.a
#                        (~16 s; SKIP without vendor/pnut).
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
    rm -rf "$BUILDROOT"/{logs,tmp,stage-a,chain,asm,asm-light,stage0,handoff,pnut,pnut-amd64}
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
SKIP=0
run() {
    local name=$1; shift
    local t=$SECONDS rc=0
    printf '%-18s' "$name ..."
    "$@" > "$LOGS/$name.log" 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then
        echo " OK   ($((SECONDS - t))s)"; PASS=$((PASS + 1))
    elif [ "$rc" = 77 ]; then
        echo " SKIP ($(grep -m1 'SKIP' "$LOGS/$name.log" | sed 's/^[^:]*: SKIP: //'))"; SKIP=$((SKIP + 1))
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
run 6-stage0         env BUILDROOT="$BUILDROOT/stage0" BOOTSTRAP_OUT="$BUILDROOT/chain/bootstrap/out" tests/cc/stage0-check.sh
run 7-handoff        env BUILDROOT="$BUILDROOT/handoff" BOOTSTRAP_OUT="$BUILDROOT/chain/bootstrap/out" ./handoff.sh
run 8-pnut           env BUILDROOT="$BUILDROOT/pnut" BOOTSTRAP_OUT="$BUILDROOT/chain/bootstrap/out" SF_PNUT_TCC=1 tests/pnut/sf-pnut-check.sh
run 9-pnut-amd64     env BUILDROOT="$BUILDROOT/pnut-amd64" SF_PNUT64_GCC_ORACLE=1 tests/pnut/sf-pnut-amd64-check.sh

echo
grep -h 'stage-a-check: self\|^A: \|^F: \|^M2-Planet tests:\|byte-identical\|DDC\|match [a-z0-9]*\.answers\|^handoff: PASS\|^stage0-check: PASS\|^sf-pnut-check: stage\|^sf-pnut-amd64-check: .*tcc-boot2 = tcc-boot3\|^sf-pnut-amd64-check: reference' "$LOGS"/*.log | grep -v '^===' | sed 's/^/  /' || true
echo
if [ "$FAIL" = 0 ] && [ "$SKIP" = 0 ]; then
    echo "verify: all $PASS steps PASS in $((SECONDS - T0))s"
elif [ "$FAIL" = 0 ]; then
    echo "verify: $PASS PASS, $SKIP SKIP, 0 FAIL in $((SECONDS - T0))s"
else
    echo "verify: $FAIL FAIL, $PASS PASS, $SKIP SKIP"; exit 1
fi
