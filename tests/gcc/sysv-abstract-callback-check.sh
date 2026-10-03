#!/usr/bin/env bash
# Abstract callback parameters preserve nested signatures and pointer returns.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-abstract-callback.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-compile.sh tests/gcc/sysv-abstract-callback.c "$work/mapped"
"$work/mapped"
tests/gcc/sysv-object-compile.sh tests/gcc/sysv-abstract-callback.c "$work/fixture.o"
${CC:-cc} -fno-pie -no-pie "$work/fixture.o" -o "$work/object-check"
"$work/object-check"
${CC:-cc} -std=c90 -pedantic-errors -O2 tests/gcc/sysv-abstract-callback.c -o "$work/reference"
"$work/reference"
echo 'PASS: unnamed/named pointer-returning callback signatures and calls'
while IFS='|' read -r label code source; do
  printf '%s\n' "$source" > "$work/reject.c"
  rc=0
  tests/gcc/sysv-object-compile.sh "$work/reject.c" "$work/reject.o" >"$work/reject.log" 2>&1 || rc=$?
  if [ "$rc" != "$code" ]; then
    cat "$work/reject.log" >&2
    echo "FAIL: $label returned $rc, expected $code" >&2
    exit 1
  fi
  echo "PASS: $label rejects with $code"
done <<'CASES'
callback-return-conflict|237|int f(int *(*)(int)); int f(long *(*p)(int));
callback-parameter-conflict|237|int f(int (*)(int)); int f(int (*p)(long));
callback-unnamed-definition|233|int f(int (*)(int)){return 0;}
anonymous-object-declarator|203|int (*)(int);
CASES
