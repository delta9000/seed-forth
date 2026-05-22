#!/usr/bin/env bash
# Stage-0 of the bootstrap-gap-closing chain (Ch 33-37, in progress):
# drive 130-asm.fth on the exit42 fixture and verify it produces an ELF
# byte-identical to mescc-tools' M1+hex2 reference pipeline.
#
# What this proves:
#   - forth-asm (in Forth, ~250 lines) can consume hex2 text and emit ELF
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
if [ ! -x "$MESCC_DIR/bin/M1" ] || [ ! -x "$MESCC_DIR/bin/hex2" ]; then
    (cd "$MESCC_DIR" && make >/dev/null 2>&1) || fail "make mescc-tools failed"
fi
[ -x "$MESCC_DIR/bin/M1" ]   || fail "$MESCC_DIR/bin/M1 not produced"
[ -x "$MESCC_DIR/bin/hex2" ] || fail "$MESCC_DIR/bin/hex2 not produced"

# --- Reference pipeline: M1 then hex2 -> exit42-ref ---
"$MESCC_DIR/bin/M1" \
    --architecture amd64 --little-endian \
    -f "$M2LIBC/amd64_defs.M1" \
    -f tests/asm/exit42.M1 \
    -o "$BUILDROOT/exit42.hex2" \
    || fail "reference M1 failed"

"$MESCC_DIR/bin/hex2" \
    --architecture amd64 --little-endian \
    --base-address 0x00600000 \
    -f "$M2LIBC/ELF-amd64.hex2" \
    -f "$BUILDROOT/exit42.hex2" \
    -o "$BUILDROOT/exit42-ref" \
    || fail "reference hex2 failed"

# --- Forth-asm pipeline: 130-asm.fth consumes (ELF prefix + .hex2) on stdin ---
strip_forth() { sed -e 's/\\.*$//' -e 's/([^)]*)//g' | grep -v '^[[:space:]]*$'; }

{ cat 010-lib.fth 130-asm.fth | strip_forth ;
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
