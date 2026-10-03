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
floating-return-call|232|double f(void); int g(void){f(); return 0;}
floating-argument-call|232|void f(double); int g(void){f(1); return 0;}
aggregate-return-call|232|struct S{int x;}; struct S f(void); int g(void){f(); return 0;}
aggregate-argument-call|232|struct S{int x;}; void f(struct S); int g(void){struct S s={1}; f(s); return 0;}
floating-return-definition|232|double f(void){return 0;}
floating-parameter-definition|232|int f(double x){return 0;}
floating-local-load|232|int f(void){double x; return x;}
floating-global-load|232|extern double x; int f(void){return x;}
floating-pointer-load|232|int f(double *p){return *p;}
floating-pointer-store|232|int f(double *p){*p=0; return 0;}
floating-runtime-cast|232|int f(void){return (int)(double)1;}
floating-static-value|232|double x=0;
floating-static-field|232|struct S{int x; double y;}; struct S s={1,0};
floating-static-cast|240|int x=(int)(double)1;
default-float-promotion-conflict|237|int f(); int f(float x);
CASES
