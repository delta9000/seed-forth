#!/usr/bin/env bash
# Production paths are entirely Forth-generated. Host oracles are opt-in.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-function-casts.XXXXXX)
trap 'rm -rf "$work"' EXIT
fixture=tests/gcc/sysv-function-pointer-casts.c
tests/gcc/sysv-compile.sh "$fixture" "$work/mapped"
"$work/mapped"
python3 tools/gcc-direct-cc.py "$fixture" -o "$work/linked"
"$work/linked"
echo 'PASS: function-pointer round trips, typed calls and nested result metadata in Forth-only ELF/object paths'
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
function-to-narrow-integer|230|int f(void); int g(void){return (int)f;}
object-to-function|230|int g(void *p){return ((int (*)(void))p)();}
function-to-object|230|int f(void); void *g(void){return (void *)f;}
function-to-char-double-pointer|230|int f(void); char **g(void){return (char **)f;}
object-to-typedef-function|230|typedef int (*F)(void); int g(char **p){return ((F)p)();}
function-to-function-pointer-object|230|typedef int (*F)(void); int f(void); F *g(void){return (F *)f;}
float-return-call|232|float f(void); int g(void){void (*p)()=(void (*)())f; ((float (*)(void))p)(); return 0;}
double-argument-call|232|int f(double); int g(void){void (*p)()=(void (*)())f; return ((int (*)(double))p)(1);}
aggregate-return-call|232|struct S{int x;}; struct S f(void); int g(void){void (*p)()=(void (*)())f; ((struct S (*)(void))p)(); return 0;}
aggregate-argument-call|232|struct S{int x;}; int f(struct S); int g(void){struct S s; void (*p)()=(void (*)())f; return ((int (*)(struct S))p)(s);}
wrong-argument-count|235|int f(int); int g(void){void (*p)()=(void (*)())f; return ((int (*)(int))p)();}
extra-function-pointer-indirection|231|int f(void); int g(void){return ((int (**)(void))f)();}
CASES
if [ "${SF_GCC_CAST_ORACLE:-0}" = 1 ]; then
  for optimization in 0 2; do
    "${CC:-cc}" -std=c90 -pedantic-errors -Wno-overflow -O"$optimization" "$fixture" -o "$work/host-O$optimization"
    "$work/host-O$optimization"
  done
  tests/gcc/sysv-object-compile.sh "$fixture" "$work/fixture.o"
  "${CC:-cc}" -fno-pie -no-pie "$work/fixture.o" -o "$work/host-linked"
  "$work/host-linked"
  echo 'PASS: separate host O0/O2 semantic oracles and host-linked Forth object'
fi
