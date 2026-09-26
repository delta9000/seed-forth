#!/usr/bin/env bash
# Builds mescc-tools' M1 and hex2 binaries entirely via our chain:
#   forth-cc compiles M2-Planet.c (via build-m2planet-monolith.sh, leveraged
#   by m2planet-check.sh)  ->  forth-asm produces a runnable M2-Planet  ->
#   that M2-Planet compiles mescc-tools' M1-macro.c / hex2*.c  ->  forth-asm
#   assembles the result into native M1 and hex2 binaries.
#
# A COMPARISON AGAINST GCC-BUILT REFERENCES: verifies byte-identity vs the
# same M1+hex2 pipeline run with mescc-tools' GCC-built binaries, and runs
# each produced tool on a tiny input to confirm the binaries are
# functionally correct.  (bootstrap.sh builds the same M1 and hex2 with no
# GCC reference anywhere.)
#
# Rebuilds everything it compares every run: m2planet-check.sh (and through
# it stage-a-check.sh) always runs first, and the GCC M1/hex2 are rebuilt by
# tests/cc/build-gcc-refs.sh.

set -euo pipefail
cd "$(dirname "$0")/../.."

MESCC_DIR=vendor/mescc-tools
M2LIBC=vendor/M2-Planet/M2libc/amd64
BUILDROOT=${BUILDROOT:-/tmp/seed-bootstrap}
M2_BIN=$BUILDROOT/m2-via-forth-asm

fail() { printf 'asm/mescc-tools-check: FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'asm/mescc-tools-check: %s\n' "$1"; }

[ -x seed-forth ] || ./build.sh >/dev/null
[ -x seed-forth ] || fail "seed-forth build failed"

# m2-via-forth-asm is produced by m2planet-check.sh; rebuild it every run.
rm -f "$M2_BIN"
pass "running m2planet-check.sh to (re)build $M2_BIN..."
BUILDROOT=$BUILDROOT tests/asm/m2planet-check.sh >/dev/null || fail "m2planet-check failed"
[ -x "$M2_BIN" ] || fail "$M2_BIN not produced"
tests/cc/build-gcc-refs.sh "$BUILDROOT/gcc-ref" >/dev/null || fail "gcc reference build failed"

# build_via_forth_asm <name> <c-source-files...>
\
\
# Stages: m2-via-forth-asm compiles C sources to M1, then forth-asm assembles.
build_via_forth_asm() {
    local name=$1; shift
    local srcs=( "$@" )

    # Step 1: compile C sources via the forth-asm-built M2-Planet.
    local m2_args=()
    for s in "${srcs[@]}"; do m2_args+=( -f "$s" ); done
    (cd "$MESCC_DIR" && "$M2_BIN" --architecture amd64 --expand-includes \
        "${m2_args[@]}" -o "$BUILDROOT/$name.M1") \
        || fail "$name: m2-via-forth-asm failed"

    # Step 2 (reference): mescc-tools M1 + hex2 on the same C-derived M1.
    "$BUILDROOT/gcc-ref/M1-ref" --architecture amd64 --little-endian \
        -f "$M2LIBC/amd64_defs.M1" \
        -f "$M2LIBC/libc-full.M1" \
        -f "$BUILDROOT/$name.M1" \
        -o "$BUILDROOT/$name.hex2" \
        || fail "$name: reference M1 failed"
    "$BUILDROOT/gcc-ref/hex2-ref" --architecture amd64 --little-endian \
        --base-address 0x00600000 \
        -f "$M2LIBC/ELF-amd64.hex2" \
        -f "$BUILDROOT/$name.hex2" \
        -o "$BUILDROOT/$name-via-mescc" \
        || fail "$name: reference hex2 failed"

    # Step 3: forth-asm produces the same binary.
    { cat 010-lib.fth 130-asm.fth ;
      printf 'asm-main\n' ;
      cat "$M2LIBC/amd64_defs.M1" ;
      cat "$M2LIBC/ELF-amd64.hex2" ;
      cat "$M2LIBC/libc-full.M1" ;
      cat "$BUILDROOT/$name.M1" ;
    } > "$BUILDROOT/forth-asm-$name-input.txt"
    rm -f /tmp/asm-out
    ./seed-forth < "$BUILDROOT/forth-asm-$name-input.txt" \
        || fail "$name: seed-forth exited non-zero"
    [ -f /tmp/asm-out ] || fail "$name: /tmp/asm-out not produced"

    if cmp -s "$BUILDROOT/$name-via-mescc" /tmp/asm-out; then
        pass "$name: byte-identical to reference ($(wc -c < /tmp/asm-out) bytes)"
    else
        fail "$name: forth-asm output differs from mescc-tools reference"
    fi

    chmod +x /tmp/asm-out
    cp /tmp/asm-out "$BUILDROOT/$name-via-forth-asm"
}

# --- M1 ---
pass "building M1 via forth-asm chain..."
build_via_forth_asm M1 M2libc/bootstrappable.c stringify.c M1-macro.c

# Behavioral check: assemble a tiny .M1 with both M1 binaries; cmp.
printf ':a\nDEFINE foo 42\nfoo\n:end\n' > "$BUILDROOT/tiny.M1"
"$BUILDROOT/M1-via-forth-asm" --architecture amd64 -f "$BUILDROOT/tiny.M1" \
    -o "$BUILDROOT/tiny-via-our-M1.hex2"
"$BUILDROOT/gcc-ref/M1-ref" --architecture amd64 -f "$BUILDROOT/tiny.M1" \
    -o "$BUILDROOT/tiny-via-ref-M1.hex2"
if cmp -s "$BUILDROOT/tiny-via-our-M1.hex2" "$BUILDROOT/tiny-via-ref-M1.hex2"; then
    pass "M1: behavioral match on tiny .M1 input"
else
    fail "M1: behavioral output differs"
fi

# --- hex2 ---
pass "building hex2 via forth-asm chain..."
build_via_forth_asm hex2 M2libc/bootstrappable.c hex2_linker.c hex2_word.c hex2.c

printf ':a\n7F 45 4C 46\n:end\n' > "$BUILDROOT/tiny.hex2"
"$BUILDROOT/hex2-via-forth-asm" --architecture amd64 --little-endian \
    --base-address 0 -f "$BUILDROOT/tiny.hex2" \
    -o "$BUILDROOT/tiny-via-our-hex2" --non-executable 2>/dev/null
"$BUILDROOT/gcc-ref/hex2-ref" --architecture amd64 --little-endian \
    --base-address 0 -f "$BUILDROOT/tiny.hex2" \
    -o "$BUILDROOT/tiny-via-ref-hex2" --non-executable 2>/dev/null
if cmp -s "$BUILDROOT/tiny-via-our-hex2" "$BUILDROOT/tiny-via-ref-hex2"; then
    pass "hex2: behavioral match on tiny .hex2 input"
else
    fail "hex2: behavioral output differs"
fi

pass "PASS"
