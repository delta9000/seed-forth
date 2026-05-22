#!/usr/bin/env bash
# Phase-2a fixture: verifies forth-asm handles the '!label' 1-byte
# relative ref by byte-matching mescc-tools on a jump-over program.
# Hex2-format input (not M1) — fed directly to hex2 as the reference.
# Numeric sigil form ('!3', '%60', etc.) is exercised end-to-end once
# phase 2b's M1 macro layer lands.

set -euo pipefail
cd "$(dirname "$0")/../.."

MESCC_DIR=vendor/mescc-tools
M2LIBC=$MESCC_DIR/M2libc/amd64
BUILDROOT=${BUILDROOT:-/tmp/forth-asm-smoke}

fail() { printf 'asm/jump42-check: FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'asm/jump42-check: %s\n' "$1"; }

mkdir -p "$BUILDROOT"

[ -x seed-forth ] || ./build.sh >/dev/null
[ -x seed-forth ] || fail "seed-forth build failed"

if [ ! -x "$MESCC_DIR/bin/hex2" ]; then
    (cd "$MESCC_DIR" && make >/dev/null 2>&1) || fail "make mescc-tools failed"
fi

# Reference: hex2 alone (no M1 needed — fixture is already hex2 format).
"$MESCC_DIR/bin/hex2" \
    --architecture amd64 --little-endian \
    --base-address 0x00600000 \
    -f "$M2LIBC/ELF-amd64.hex2" \
    -f tests/asm/jump42.hex2 \
    -o "$BUILDROOT/jump42-ref" \
    || fail "reference hex2 failed"

# Forth-asm: same hex2 inputs concatenated on stdin.
strip_forth() { sed -e 's/\\.*$//' -e 's/([^)]*)//g' | grep -v '^[[:space:]]*$'; }
{ cat 010-lib.fth 130-asm.fth | strip_forth ;
  cat "$M2LIBC/ELF-amd64.hex2" ;
  cat tests/asm/jump42.hex2 ; } > "$BUILDROOT/forth-asm-jump42-input.txt"

rm -f /tmp/asm-out
./seed-forth < "$BUILDROOT/forth-asm-jump42-input.txt" \
    || fail "seed-forth exited non-zero"
[ -f /tmp/asm-out ] || fail "/tmp/asm-out not produced"

if cmp -s "$BUILDROOT/jump42-ref" /tmp/asm-out; then
    pass "byte-identical to reference ($(wc -c < /tmp/asm-out) bytes)"
else
    cmp "$BUILDROOT/jump42-ref" /tmp/asm-out || true
    echo "--- reference ---"; od -A x -t x1 "$BUILDROOT/jump42-ref"
    echo "--- forth-asm ---"; od -A x -t x1 /tmp/asm-out
    fail "forth-asm output differs from reference"
fi

chmod +x /tmp/asm-out
set +e; /tmp/asm-out; rc=$?; set -e
[ "$rc" -eq 42 ] || fail "binary exited $rc (expected 42)"
pass "binary exits 42"
pass "PASS"
