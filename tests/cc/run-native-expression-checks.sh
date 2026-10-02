#!/usr/bin/env bash
# Focused expression regressions for the direct Forth-to-native C route.
# Host compilers are not used: compile-native.sh only drives seed-forth.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-native-expr.XXXXXX)
trap 'rm -rf "$work"' EXIT
if (($# == 0)); then
  set -- tests/cc/T1-const-short-circuit.c tests/cc/T2-native-expressions.c \
    tests/cc/T3-native-stack-calls.c tests/cc/T4-native-expression-edges.c \
    tests/cc/T5-native-strings.c tests/cc/T6-native-void-qsort.c
fi
for file in "$@"; do
  tests/tcc/compile-native.sh "$file" "$work/program"
  status=0
  "$work/program" || status=$?
  if [[ $status != 0 ]]; then
    echo "FAIL: $file -> $status" >&2
    exit 1
  fi
  echo "PASS: $file -> 0"
done

# Dead arms still need valid syntax; live division by zero must still fail.
while IFS='|' read -r label code expr; do
  printf '#if %s\n#endif\nint main() { return 0; }\n' "$expr" > "$work/reject.c"
  status=0
  tests/tcc/compile-native.sh "$work/reject.c" "$work/reject" \
    > "$work/reject.log" 2>&1 || status=$?
  if [[ $status != "$code" ]]; then
    cat "$work/reject.log" >&2
    echo "FAIL: $label expected error $code, got $status" >&2
    exit 1
  fi
  echo "PASS: $label -> error $code"
done <<'CASES'
live-and-divisor|124|1 && (1 / 0)
live-or-divisor|124|0 || (1 / 0)
live-true-divisor|124|1 ? (1 / 0) : 7
live-false-divisor|124|0 ? 7 : (1 / 0)
dead-arm-syntax|126|0 && (1 + )
CASES
