#!/usr/bin/env bash
# Smallest end-to-end check of 130-asm.fth (book Ch 33):
# drive 130-asm.fth on the exit42 fixture and verify it produces an ELF
# byte-identical to mescc-tools' M1+hex2 reference pipeline.
#
# What this proves:
#   - forth-asm (130-asm.fth, 689 lines of Forth) can consume hex2 text and emit ELF
#     bytes that match the GCC-built mescc-tools reference exactly.
#   - The resulting binary runs and exits with code 42.
#
# What this does NOT yet prove (phase 2 work):
#   - 1/2/3-byte sigils (! @ ~) — exit42 only uses '&' and '%'.
#   - M1 macro expansion (we feed post-M1 hex2 text here).
#   - Scale to M2-Planet's own M1 output.

set -euo pipefail
cd "$(dirname "$0")/../.."

MESCC_DIR=vendor/mescc-tools
M2LIBC=$MESCC_DIR/M2libc/amd64
BUILDROOT=${BUILDROOT:-/tmp/forth-asm-smoke}

fail() { printf 'asm/exit42-check: FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'asm/exit42-check: %s\n' "$1"; }

mkdir -p "$BUILDROOT"

# --- Build seed-forth if needed ---
[ -x seed-forth ] || ./build.sh >/dev/null
[ -x seed-forth ] || fail "seed-forth build failed"

# --- Build mescc-tools binaries (GCC-built reference) ---
# GCC-built mescc-tools reference, rebuilt fresh (never a stale bin/).
tests/cc/build-gcc-refs.sh "$BUILDROOT/gcc-ref" >/dev/null || fail "gcc reference build failed"

# --- Reference pipeline: M1 then hex2 -> exit42-ref ---
"$BUILDROOT/gcc-ref/M1-ref" \
    --architecture amd64 --little-endian \
    -f "$M2LIBC/amd64_defs.M1" \
    -f tests/asm/exit42.M1 \
    -o "$BUILDROOT/exit42.hex2" \
    || fail "reference M1 failed"

"$BUILDROOT/gcc-ref/hex2-ref" \
    --architecture amd64 --little-endian \
    --base-address 0x00600000 \
    -f "$M2LIBC/ELF-amd64.hex2" \
    -f "$BUILDROOT/exit42.hex2" \
    -o "$BUILDROOT/exit42-ref" \
    || fail "reference hex2 failed"

# --- Forth-asm pipeline: 130-asm.fth consumes (ELF prefix + .hex2) on stdin ---

{ cat 010-lib.fth 130-asm.fth ;
  printf 'asm-main\n' ;
  cat "$M2LIBC/ELF-amd64.hex2" ;
  cat "$BUILDROOT/exit42.hex2" ; } > "$BUILDROOT/forth-asm-input.txt"

rm -f /tmp/asm-out
./seed-forth < "$BUILDROOT/forth-asm-input.txt" \
    || fail "seed-forth exited non-zero"
[ -f /tmp/asm-out ] || fail "/tmp/asm-out not produced by forth-asm"

# --- Byte-identity check ---
if cmp -s "$BUILDROOT/exit42-ref" /tmp/asm-out; then
    pass "byte-identical to reference ($(wc -c < /tmp/asm-out) bytes)"
else
    cmp "$BUILDROOT/exit42-ref" /tmp/asm-out || true
    fail "forth-asm output differs from reference"
fi

# --- Execute the forth-asm-produced binary ---
chmod +x /tmp/asm-out
set +e
/tmp/asm-out
rc=$?
set -e
[ "$rc" -eq 42 ] || fail "forth-asm binary exited $rc (expected 42)"
pass "forth-asm-built binary exits 42"
pass "PASS"
