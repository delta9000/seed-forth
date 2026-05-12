#!/usr/bin/env bash
# Stage-A parity check — the key invariant for seed-forth correctness.
#
# Verifies that seed-forth-compiled M2-Planet (cc-out-v1) produces the same
# .M1 output as the gcc-built reference (m2-ref) when self-compiling
# M2-Planet for amd64.  This is the "A" sub-stage of bootstrap-chain.sh
# extracted into a standalone, faster script.
#
# Unlike bootstrap-chain.sh, this does NOT run stages B–G (M1/hex2 assembly,
# v2/v3 self-compile, fixed-point, hello smoke test).  Those exercise
# M2-Planet's self-hosting properties, not our compiler's correctness.
#
# Env overrides:
#   M2_PLANET   - path to M2-Planet checkout  (default vendor/M2-Planet)
#   BUILDROOT   - artifact directory          (default /tmp/seed-bootstrap)

set -euo pipefail
cd "$(dirname "$0")/../.."

M2_PLANET=${M2_PLANET:-vendor/M2-Planet}
BUILDROOT=${BUILDROOT:-/tmp/seed-bootstrap}

mkdir -p "$BUILDROOT"

fail() { printf 'stage-a-check: FAIL: %s\n' "$1" >&2; exit 1; }

# --- Build seed-forth if needed ---
[ -x seed-forth ] || ./build.sh >/dev/null
[ -x seed-forth ] || fail "seed-forth build failed"

[ -f "$M2_PLANET/cc.c" ] || fail "M2_PLANET=$M2_PLANET is not initialized (run git submodule update --init --recursive)"
[ -f "$M2_PLANET/M2libc/bootstrappable.c" ] || fail "M2_PLANET/M2libc is not initialized (run git submodule update --init --recursive)"

# --- Build m2-ref (gcc reference) if needed ---
if [ ! -x "$BUILDROOT/m2-ref" ]; then
    (cd "$M2_PLANET" && make >/dev/null 2>&1) || fail "make M2-Planet (reference) failed"
    cp "$M2_PLANET/bin/M2-Planet" "$BUILDROOT/m2-ref"
fi
[ -x "$BUILDROOT/m2-ref" ] || fail "$BUILDROOT/m2-ref not produced"

# --- Build cc-out-v1 (seed-forth compiles M2-Planet monolith) ---
rm -f /tmp/cc-out
./tests/cc/build-m2planet-monolith.sh >/dev/null || fail "monolith build failed"
[ -x /tmp/cc-out ] || fail "/tmp/cc-out not produced"
cp /tmp/cc-out "$BUILDROOT/cc-out-v1"

# --- Stage A: M1 parity for amd64 ---
m2_srcs=(M2libc/bootstrappable.c cc_reader.c cc_strings.c cc_types.c
         cc_emit.c cc_core.c cc_macro.c cc.c cc.h cc_globals.c gcc_req.h)
m2_args=()
for s in "${m2_srcs[@]}"; do m2_args+=( -f "$s" ); done

ARCH=amd64

(cd "$M2_PLANET" && "$BUILDROOT/cc-out-v1" --architecture "$ARCH" --expand-includes \
    "${m2_args[@]}" -o "$BUILDROOT/self-v1-$ARCH.M1") \
    || fail "v1 self-compile ($ARCH) failed"

(cd "$M2_PLANET" && "$BUILDROOT/m2-ref" --architecture "$ARCH" --expand-includes \
    "${m2_args[@]}" -o "$BUILDROOT/self-ref-$ARCH.M1") \
    || fail "reference self-compile ($ARCH) failed"

cmp "$BUILDROOT/self-v1-$ARCH.M1" "$BUILDROOT/self-ref-$ARCH.M1" \
    || fail "v1 != reference at $ARCH"

echo "stage-a-check: self-v1-$ARCH.M1 == self-ref-$ARCH.M1 ($(wc -c < "$BUILDROOT/self-v1-$ARCH.M1") bytes)"
echo "stage-a-check: PASS"
