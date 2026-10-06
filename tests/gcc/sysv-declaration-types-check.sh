#!/usr/bin/env bash
# Unsupported value classes may appear in declarations without fake ABI code.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-types.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-object-compile.sh tests/gcc/sysv-declaration-types.c "$work/types.o"
${CC:-cc} -O2 -Wall -Wextra -fno-pie -no-pie \
  tests/gcc/sysv-declaration-types-host.c "$work/types.o" -o "$work/check"
"$work/check"
echo 'PASS: declaration metadata, real sizes/alignment and floating-base pointers'
while IFS='|' read -r label code source; do
  printf '%s\n' "$source" > "$work/reject.c"
  printf 'previous artifact\n' > "$work/reject.o"
  rc=0
  tests/gcc/sysv-object-compile.sh "$work/reject.c" "$work/reject.o" >"$work/reject.log" 2>&1 || rc=$?
  if [ "$rc" != "$code" ] || [ "$(cat "$work/reject.o")" != 'previous artifact' ]; then
    cat "$work/reject.log" >&2
    echo "FAIL: $label returned $rc, expected $code with preserved output" >&2
    exit 1
  fi
  echo "PASS: $label rejects with $code and preserves output"
done <<'CASES'
extended-return-call|249|long double f(void); int g(void){return f();}
extended-argument-call|249|void f(long double); int g(void){f(1); return 0;}
aggregate-return-call|232|struct S{double x;}; struct S f(void); int g(void){f(); return 0;}
aggregate-argument-call|232|struct S{double x;}; void f(struct S); int g(void){struct S s={1}; f(s); return 0;}
extended-return-definition|249|long double f(void){return 0;}
extended-parameter-definition|249|int f(long double x){return x;}
extended-local-load|249|int f(void){long double x; return x;}
extended-global-load|249|extern long double x; int f(void){return x;}
extended-pointer-load|249|int f(long double *p){return *p;}
extended-pointer-store|249|int f(long double *p){*p=0; return 0;}
extended-runtime-cast|249|int f(void){return (int)(long double)1;}
default-float-promotion-conflict|237|int f(); int f(float x);
CASES
