#!/usr/bin/env bash
# Compile the pinned portable C libc and fixture together through seed-forth.
# Source staging is separate; this harness invokes no host C toolchain.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LIBC=${1:-"$ROOT/build-out/direct-tcc-sources/libc64"}
if [ ! -f "$LIBC/libc.c" ]; then
    echo "Missing staged portable-libc source: $LIBC/libc.c" >&2
    echo 'Run tests/tcc/prep-stage-sources.py first, or pass its libc64 directory.' >&2
    exit 1
fi
LIBC=$(realpath "$LIBC")
OUT=${SF_NATIVE_RUNTIME_OUT:-"$ROOT/build-out/native-runtime"}
mkdir -p "$OUT"
OUT=$(realpath "$OUT")
WORK=$(mktemp -d "$OUT/libc.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
SF_NATIVE_FLOATBITS=1 "$ROOT/tests/tcc/compile-native.sh" \
    "$ROOT/tests/tcc/native-runtime-libc.c" "$WORK/runtime" \
    "$LIBC" "$LIBC/include"
"$WORK/runtime" "$WORK/io.bin" >"$WORK/stdout" 2>"$WORK/stderr"
printf '1:2:3:4:5:6:7:8\n' >"$WORK/expected"
cmp "$WORK/expected" "$WORK/stdout"
test ! -s "$WORK/stderr"
test ! -e "$WORK/io.bin"
echo 'PASS: actual portable libc FILE operations, failed fopen, and stack varargs'
