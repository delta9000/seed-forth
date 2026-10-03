#!/usr/bin/env bash
# The production side is Forth only; this gate needs no host C compiler.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-check.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-compile.sh tests/gcc/sysv-scalars.c "$work/scalars"
"$work/scalars"
echo 'PASS: System V scalar calls, nested temporaries, recursion, pointer calls, widths'
while IFS='|' read -r name code source; do
  printf '%s\n' "$source" > "$work/reject.c"
  rc=0
  tests/gcc/sysv-compile.sh "$work/reject.c" "$work/reject" >"$work/reject.log" 2>&1 || rc=$?
  if [ "$rc" != "$code" ]; then
    cat "$work/reject.log" >&2
    echo "FAIL: $name returned $rc, expected $code" >&2
    exit 1
  fi
  echo "PASS: $name rejects with $code"
done <<'CASES'
aggregate-parameter|232|struct S { double x; }; int f(struct S s) { return s.x; } int main(void) { return 0; }
aggregate-return|232|struct S { double x; }; struct S f(void) { struct S s={1}; return s; } int main(void) { return 0; }
floating-parameter|232|int f(double x) { return 0; } int main(void) { return 0; }
missing-argument|235|int f(int x) { return x; } int main(void) { return f(); }
excess-argument|235|int f(void) { return 0; } int main(void) { return f(1); }
conflicting-prototype|237|int f(int x); long f(int x) { return x; } int main(void) { return 0; }
CASES
