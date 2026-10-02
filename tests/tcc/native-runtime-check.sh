#!/usr/bin/env bash
# Direct Forth compiler/runtime integration. No host compiler or object inputs.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${SF_NATIVE_RUNTIME_OUT:-"$ROOT/build-out/native-runtime"}
mkdir -p "$OUT"
OUT=$(realpath "$OUT")
WORK=$(mktemp -d "$OUT/run.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
expect_undefined() {
    local source=$1 output=$2 floatbits=$3 expected=${4:-206} status
    set +e
    SF_NATIVE_FLOATBITS="$floatbits" "$ROOT/tests/tcc/compile-native.sh" "$source" "$output" >"$output.stdout" 2>"$output.stderr"
    status=$?
    set -e
    if [ "$status" != "$expected" ]; then
        echo "FAIL: expected error $expected, got $status for $source" >&2
        cat "$output.stderr" >&2
        exit 1
    fi
    test ! -e "$output"
}
for source in native-runtime native-runtime-stack native-runtime-exit; do
    "$ROOT/tests/tcc/compile-native.sh" "$ROOT/tests/tcc/$source.c" "$WORK/$source"
done
"$WORK/native-runtime" "$WORK/io.bin" "$WORK/created" >"$WORK/runtime.out"
printf 'native-runtime-ok\n' >"$WORK/runtime.expected"
cmp "$WORK/runtime.expected" "$WORK/runtime.out"
test ! -e "$WORK/io.bin"
test -d "$WORK/created"
"$WORK/native-runtime-stack"
set +e
"$WORK/native-runtime-exit" >"$WORK/exit.out"
status=$?
set -e
test "$status" = 37
printf 'native-exit-ok\n' >"$WORK/exit.expected"
cmp "$WORK/exit.expected" "$WORK/exit.out"
cat >"$WORK/undefined.c" <<'SOURCE'
int unsupported_kernel_primitive(void);
int main(void) { return unsupported_kernel_primitive(); }
SOURCE
expect_undefined "$WORK/undefined.c" "$WORK/undefined" 0
for name in localtime ldexp longjmp; do
    source="$ROOT/tests/tcc/native-runtime-$name.c"
    # The narrow unsupported allow-list exists only in float-bit seed mode.
    expected=206
    [ "$name" != ldexp ] || expected=214  # its double declaration is seed-only too
    expect_undefined "$source" "$WORK/normal-$name" 0 "$expected"
    SF_NATIVE_FLOATBITS=1 "$ROOT/tests/tcc/compile-native.sh" "$source" "$WORK/seed-$name"
    set +e
    "$WORK/seed-$name" >"$WORK/seed-$name.out" 2>"$WORK/seed-$name.err"
    status=$?
    set -e
    test "$status" = 125
    test ! -s "$WORK/seed-$name.out"
    printf 'seed-forth bootstrap: unsupported %s\n' "$name" >"$WORK/seed-$name.expected"
    cmp "$WORK/seed-$name.expected" "$WORK/seed-$name.err"
done
expect_undefined "$WORK/undefined.c" "$WORK/seed-undefined" 1
echo 'PASS: native syscalls, 64-bit seek, eight stack slots, exit, strict undefined calls, three fail-closed seed traps'
