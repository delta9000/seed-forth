#!/usr/bin/env bash
# Phase-2b fixture: M1 source with DEFINE macros + numeric '%N' sigils.
# Reference pipeline: M1 then hex2.  Forth-asm consumes the same .M1 +
# the amd64 defs + the ELF prefix directly (uniform path).

set -euo pipefail
cd "$(dirname "$0")/../.."

MESCC_DIR=vendor/mescc-tools
M2LIBC=$MESCC_DIR/M2libc/amd64
BUILDROOT=${BUILDROOT:-/tmp/forth-asm-smoke}

fail() { printf 'asm/m1-jump42-check: FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'asm/m1-jump42-check: %s\n' "$1"; }

mkdir -p "$BUILDROOT"

[ -x seed-forth ] || ./build.sh >/dev/null
[ -x seed-forth ] || fail "seed-forth build failed"

if [ ! -x "$MESCC_DIR/bin/M1" ] || [ ! -x "$MESCC_DIR/bin/hex2" ]; then
    (cd "$MESCC_DIR" && make >/dev/null 2>&1) || fail "make mescc-tools failed"
fi

# Reference: M1(amd64_defs + m1-jump42) -> hex2 text -> hex2(ELF + that) -> ELF.
"$MESCC_DIR/bin/M1" \
    --architecture amd64 --little-endian \
    -f "$M2LIBC/amd64_defs.M1" \
    -f tests/asm/m1-jump42.M1 \
    -o "$BUILDROOT/m1-jump42.hex2" \
    || fail "reference M1 failed"

"$MESCC_DIR/bin/hex2" \
    --architecture amd64 --little-endian \
    --base-address 0x00600000 \
    -f "$M2LIBC/ELF-amd64.hex2" \
    -f "$BUILDROOT/m1-jump42.hex2" \
    -o "$BUILDROOT/m1-jump42-ref" \
    || fail "reference hex2 failed"

# Forth-asm: amd64_defs + m1-jump42 + ELF prefix all on stdin (uniform path).
strip_forth() { sed -e 's/\\.*$//' -e 's/([^)]*)//g' | grep -v '^[[:space:]]*$'; }
{ cat 010-lib.fth 130-asm.fth | strip_forth ;
  printf 'asm-main\n' ;
  cat "$M2LIBC/amd64_defs.M1" ;     # DEFINEs first (emit nothing)
  cat "$M2LIBC/ELF-amd64.hex2" ;    # ELF header, ends with :ELF_text
  cat tests/asm/m1-jump42.M1 ;      # :_start follows ELF_text, code, :ELF_end
} > "$BUILDROOT/forth-asm-m1-jump42-input.txt"

rm -f /tmp/asm-out
./seed-forth < "$BUILDROOT/forth-asm-m1-jump42-input.txt" \
    || fail "seed-forth exited non-zero"
[ -f /tmp/asm-out ] || fail "/tmp/asm-out not produced"

if cmp -s "$BUILDROOT/m1-jump42-ref" /tmp/asm-out; then
    pass "byte-identical to reference ($(wc -c < /tmp/asm-out) bytes)"
else
    cmp "$BUILDROOT/m1-jump42-ref" /tmp/asm-out || true
    echo "--- reference ---"; od -A x -t x1 "$BUILDROOT/m1-jump42-ref" | head -15
    echo "--- forth-asm ---"; od -A x -t x1 /tmp/asm-out | head -15
    fail "forth-asm output differs from reference"
fi

chmod +x /tmp/asm-out
set +e; /tmp/asm-out; rc=$?; set -e
[ "$rc" -eq 42 ] || fail "binary exited $rc (expected 42)"
pass "binary exits 42"
pass "PASS"
