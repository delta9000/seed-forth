#!/bin/sh
# usage: run-die-gate.sh GATE EXPECTED_CODE EXPECTED_STDERR
#
# A die gate is a C program the compiler must REJECT: it checks that the
# compiler exits with EXPECTED_CODE (Appendix G's error code) and that the
# last line it writes to stderr is EXPECTED_STDERR ("cc: line N: error C",
# from cc-die in 020-cc-arena.fth), and that no /tmp/cc-out was written.
#
# GATE is tests/cc/GATE.  A .c gate is fed as-is.  A .sh gate is a
# generator for inputs too large or too repetitive to check in: it prints
# the C source on stdout.  It may write helper files (e.g. a header to
# #include) into $CC_DIE_TMP, a scratch directory removed afterwards.
set -e

cd "$(dirname "$0")/../.."

GATE_FILE="tests/cc/$1"
EXPECTED="$2"
EXPECTED_STDERR="$3"
OUT=/tmp/cc-out
rm -f "$OUT"

[ -x seed-forth ] || ./build.sh >/dev/null

CC_DIE_TMP=$(mktemp -d)
export CC_DIE_TMP
trap 'rm -rf "$CC_DIE_TMP"' EXIT

case "$GATE_FILE" in
    *.sh) sh "$GATE_FILE" > "$CC_DIE_TMP/src.c" ;;
    *)    cp "$GATE_FILE" "$CC_DIE_TMP/src.c" ;;
esac

ACTUAL=0
cat 010-lib.fth $(tools/compiler-layers.sh) "$CC_DIE_TMP/src.c" \
    | ./seed-forth > /dev/null 2> "$CC_DIE_TMP/stderr" || ACTUAL=$?
ACTUAL_STDERR=$(tail -n 1 "$CC_DIE_TMP/stderr")

if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "FAIL: $1 expected compiler exit $EXPECTED, got $ACTUAL ($ACTUAL_STDERR)"
    exit 1
fi
if [ "$ACTUAL_STDERR" != "$EXPECTED_STDERR" ]; then
    echo "FAIL: $1 stderr mismatch."
    echo "  expected: $EXPECTED_STDERR"
    echo "  actual:   $ACTUAL_STDERR"
    exit 1
fi
if [ -f "$OUT" ]; then
    echo "FAIL: $1 died but still wrote $OUT"
    exit 1
fi
echo "PASS: $1 -> $ACTUAL ($ACTUAL_STDERR)"
