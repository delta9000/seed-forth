#!/usr/bin/env bash
# Focused regression gate for the opt-in Forth compiler. No host C toolchain.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
mkdir -p build-out
WORK=$(mktemp -d "$ROOT/build-out/native-check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
for name in basics layout stack-call for forward-types literals many-args \
    tentative-array nested-label switch-goto label-statement label-case for-lookahead; do
  tests/tcc/compile-native.sh "tests/tcc/native-$name.c" "$WORK/$name"
  "$WORK/$name"
  printf 'PASS: native-%s\n' "$name"
done
rc=0
timeout 5 tests/tcc/compile-native.sh tests/tcc/native-bad-parameters.c \
  "$WORK/bad-parameters" >"$WORK/bad-parameters.log" 2>&1 || rc=$?
[ "$rc" = 184 ] || { cat "$WORK/bad-parameters.log"; echo "FAIL: malformed parameters returned $rc"; exit 1; }
echo 'PASS: malformed parameter list rejects without hanging'
bash tests/tcc/profile-bounds-check.sh
tests/cc/run-native-expression-checks.sh
python3 tests/cc/lp64-encoders-check.py
tests/tcc/prep-check.sh
tests/tcc/initializers-check.sh
tests/tcc/native-runtime-check.sh
python3 tests/tcc/source-closure-check-test.py
