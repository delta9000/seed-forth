#!/usr/bin/env bash
# Supported grouped declarators and omitted for steps; no production host tools.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-declarator-edges.XXXXXX)
trap 'rm -rf "$work"' EXIT
fixture=tests/gcc/sysv-declarator-edges.c
tests/gcc/sysv-compile.sh "$fixture" "$work/mapped"
"$work/mapped"
tools/gcc-direct-cc.py "$fixture" -o "$work/linked"
"$work/linked"
echo 'PASS: grouped pointers, callback arrays, single evaluation and empty for steps, Forth-only mapped and linked ELF'
tests/gcc/sysv-object-compile.sh "$fixture" "$work/fixture.o"
${CC:-cc} -fno-pie -no-pie "$work/fixture.o" -o "$work/object-check"
"$work/object-check"
for opt in -O0 -O2; do
  ${CC:-cc} -std=c90 -pedantic-errors "$opt" "$fixture" -o "$work/reference"
  "$work/reference"
done
echo 'PASS: independent strict C90 O0/O2 behavior oracles and host-linked object'
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
pointer-to-array|238|int (*p)[3];
array-of-pointers-to-array|238|int (*p[2])[3];
extra-function-pointer-depth|231|int (**p[2])(int);
function-returning-array|238|int (*f(void))[3];
function-array|238|int (f[3])(int);
callback-array-zero|238|struct X {int (*f[0])(int);};
callback-array-negative|238|struct X {int (*f[-1])(int);};
grouped-return-conflict|237|int (*f(void)); long *f(void);
callback-array-argument-count|235|struct X{int (*f[3])(int);}; int g(struct X *p){return p->f[0]();}
function-object-cast|230|int f(void); char **g(void){return (char **)f;}
grouped-object-function-cast|230|int f(void); int g(void){char (**p);p=(char **)f;return 0;}
aggregate-callback-argument|232|struct S{int x;}; struct X{int (*f[3])(struct S);}; int g(struct X *p){struct S s;return p->f[0](s);}
long-double-callback-argument|232|struct X{int (*f[3])(long double);}; int g(struct X *p){return p->f[0](1);}
CASES
