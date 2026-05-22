#!/usr/bin/env bash
# Phase-2c integration: assemble a runnable M2-Planet via forth-asm.
# Reference: mescc-tools M1 + hex2 on the same inputs.  Forth-asm reads
# the concatenated stream directly (uniform path).
#
# Prereqs:
#   - tests/cc/stage-a-check.sh has run (produces self-v1-amd64.M1).
#   - vendor/mescc-tools binaries built.
#
# This is the load-bearing test: if it passes, forth-asm can drive every
# bootstrap step above hex0 without GCC in the trust chain.

set -euo pipefail
cd "$(dirname "$0")/../.."

MESCC_DIR=vendor/mescc-tools
# M2-Planet bundles its own M2libc with a fuller amd64 mnemonic vocabulary
# (mov_r13,rsp etc. are not in mescc-tools' amd64_defs.M1).  Use it.
M2LIBC=vendor/M2-Planet/M2libc/amd64
BUILDROOT=${BUILDROOT:-/tmp/seed-bootstrap}
M1_FILE=$BUILDROOT/self-v1-amd64.M1

fail() { printf 'asm/m2planet-check: FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'asm/m2planet-check: %s\n' "$1"; }

[ -x seed-forth ] || ./build.sh >/dev/null
[ -x seed-forth ] || fail "seed-forth build failed"

if [ ! -f "$M1_FILE" ]; then
    pass "self-v1-amd64.M1 missing, running stage-A to produce it..."
    tests/cc/stage-a-check.sh >/dev/null
fi
[ -f "$M1_FILE" ] || fail "$M1_FILE not produced"

if [ ! -x "$MESCC_DIR/bin/M1" ] || [ ! -x "$MESCC_DIR/bin/hex2" ]; then
    (cd "$MESCC_DIR" && make >/dev/null 2>&1) || fail "make mescc-tools failed"
fi

# --- Reference: mescc-tools M1 then hex2 ---
pass "building reference via mescc-tools M1 + hex2..."
"$MESCC_DIR/bin/M1" \
    --architecture amd64 --little-endian \
    -f "$M2LIBC/amd64_defs.M1" \
    -f "$M2LIBC/libc-full.M1" \
    -f "$M1_FILE" \
    -o "$BUILDROOT/m2-via-mescc.hex2" \
    || fail "reference M1 failed"

"$MESCC_DIR/bin/hex2" \
    --architecture amd64 --little-endian \
    --base-address 0x00600000 \
    -f "$M2LIBC/ELF-amd64.hex2" \
    -f "$BUILDROOT/m2-via-mescc.hex2" \
    -o "$BUILDROOT/m2-via-mescc" \
    || fail "reference hex2 failed"

ref_bytes=$(wc -c < "$BUILDROOT/m2-via-mescc")
pass "reference: $ref_bytes bytes"

# --- forth-asm: read amd64_defs + ELF prefix + libc + cc-code on stdin ---
pass "running forth-asm (may take a while on this much input)..."
strip_forth() { sed -e 's/\\.*$//' -e 's/([^)]*)//g' | grep -v '^[[:space:]]*$'; }
{ cat 010-lib.fth 130-asm.fth | strip_forth ;
  cat "$M2LIBC/amd64_defs.M1" ;        # DEFINEs (emit nothing)
  cat "$M2LIBC/ELF-amd64.hex2" ;       # ELF prefix, ends at :ELF_text
  cat "$M2LIBC/libc-full.M1" ;         # :_start + startup
  cat "$M1_FILE" ;                     # the cc code
} > "$BUILDROOT/forth-asm-m2-input.txt"

rm -f /tmp/asm-out
./seed-forth < "$BUILDROOT/forth-asm-m2-input.txt" \
    || fail "seed-forth exited non-zero"
[ -f /tmp/asm-out ] || fail "/tmp/asm-out not produced"

if cmp -s "$BUILDROOT/m2-via-mescc" /tmp/asm-out; then
    pass "byte-identical to mescc-tools reference ($(wc -c < /tmp/asm-out) bytes)"
else
    cmp "$BUILDROOT/m2-via-mescc" /tmp/asm-out || true
    fail "forth-asm output differs from reference"
fi

# --- Sanity: forth-asm-built M2-Planet compiles a tiny C program ---
# (We don't require self-compile fixed-point with stage-A's reference — that
# would also assert forth-cc's M1 emit equals its ELF emit, which is a
# separate property handled in stage-A.  Here we just confirm the binary
# is functionally equivalent to m2-ref on simple input.)
chmod +x /tmp/asm-out
cp /tmp/asm-out "$BUILDROOT/m2-via-forth-asm"

printf 'int main() { return 42; }\n' > "$BUILDROOT/hello.c"
"$BUILDROOT/m2-via-forth-asm" --architecture amd64 -f "$BUILDROOT/hello.c" \
    -o "$BUILDROOT/hello-via-forth-asm.M1" \
    || fail "forth-asm-built M2-Planet failed to compile hello.c"
"$BUILDROOT/m2-ref" --architecture amd64 -f "$BUILDROOT/hello.c" \
    -o "$BUILDROOT/hello-via-ref.M1"
if cmp -s "$BUILDROOT/hello-via-forth-asm.M1" "$BUILDROOT/hello-via-ref.M1"; then
    pass "forth-asm-built M2-Planet matches m2-ref on hello.c"
else
    fail "compile output differs from m2-ref"
fi

pass "PASS"
