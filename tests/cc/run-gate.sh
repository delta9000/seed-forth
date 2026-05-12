#!/bin/sh
# usage: run-gate.sh GATE.c EXPECTED_EXIT [EXPECTED_STDOUT]
#
# Concatenates the compiler vocabulary onto stdin BEFORE the C source.  The
# seed-forth REPL reads its tokens via 1-byte `key` syscalls, parsing through
# the entire stripped vocabulary; the very last word in 120-cc-main.fth is `cc-main`,
# which is invoked at REPL-time.  cc-main calls cc-load-stdin (a 4096-byte
# read on fd 0), which picks up everything remaining in the pipe — the C
# source.  cc-main ends with `bye`, so the REPL never resumes.
#
# If EXPECTED_STDOUT is provided, the produced executable's stdout is
# compared against it (after `$(...)` trims a single trailing newline).
set -e

cd "$(dirname "$0")/../.."

GATE_FILE="tests/cc/$1"
EXPECTED="$2"
EXPECTED_STDOUT="$3"
OUT=/tmp/cc-out

# Inline strip_forth (matches test.sh).
strip_forth() { sed -e 's/\\.*$//' -e 's/([^)]*)//g' | grep -v '^[[:space:]]*$'; }

# Build seed-forth if missing.
[ -x seed-forth ] || ./build.sh >/dev/null

# Step 1: write stripped vocab to a temp file (so we can concatenate it as raw
# bytes with the un-stripped C source — strip_forth would otherwise mangle the
# C identifiers and braces).
TMP_VOCAB=$(mktemp)
TMP_STDOUT=$(mktemp)
trap 'rm -f "$TMP_VOCAB" "$TMP_STDOUT"' EXIT

cat [0-9][0-9][0-9]-*.fth | strip_forth > "$TMP_VOCAB"

# Step 2: feed (vocab + C source) into seed-forth.  The REPL parses the
# Forth, hits `cc-main` and invokes it; cc-main reads the remaining bytes
# (the C source) via cc-load-stdin.
cat "$TMP_VOCAB" "$GATE_FILE" | ./seed-forth

[ -f "$OUT" ] || { echo "FAIL: $1 — $OUT not produced"; exit 1; }
chmod +x "$OUT" 2>/dev/null || true
ACTUAL=0
"$OUT" > "$TMP_STDOUT" 2>/dev/null || ACTUAL=$?
if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "FAIL: $1 expected exit $EXPECTED, got $ACTUAL"
    exit 1
fi
if [ -n "$EXPECTED_STDOUT" ]; then
    ACTUAL_STDOUT=$(cat "$TMP_STDOUT")
    if [ "$ACTUAL_STDOUT" != "$EXPECTED_STDOUT" ]; then
        echo "FAIL: $1 stdout mismatch."
        echo "  expected: $EXPECTED_STDOUT"
        echo "  actual:   $ACTUAL_STDOUT"
        exit 1
    fi
fi
echo "PASS: $1 -> $ACTUAL"
