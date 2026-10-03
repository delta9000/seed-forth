#!/usr/bin/env bash
# C90 unspecified prototypes and identifier-list definitions, Forth only.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-knr.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-compile.sh tests/gcc/sysv-knr.c "$work/knr"
"$work/knr"
echo 'PASS: C90 implicit int, K&R parameters/promotions and preserved prototypes'
while IFS='|' read -r label code source; do
  printf '%s\n' "$source" > "$work/reject.c"
  rc=0
  tests/gcc/sysv-compile.sh "$work/reject.c" "$work/reject" >"$work/reject.log" 2>&1 || rc=$?
  if [ "$rc" != "$code" ]; then
    cat "$work/reject.log" >&2
    echo "FAIL: $label returned $rc, expected $code" >&2
    exit 1
  fi
  echo "PASS: $label rejects with $code"
done <<'CASES'
unspecified-char-conflict|237|int f(); int f(char x) { return x; } int main(void){return 0;}
unspecified-variadic-conflict|237|int f(); int f(int x,...); int main(void){return 0;}
knr-count-conflict|237|int f(int,int); int f(x) int x; {return x;} int main(void){return 0;}
implicit-return-conflict|237|long f(void); f(){return 0;} int main(void){return 0;}
knr-width-conflict|237|int f(long); int f(x) int x; {return x;} int main(void){return 0;}
knr-unknown-name|233|int f(x) int y; {return x;} int main(void){return 0;}
knr-duplicate-name|233|int f(x,x) int x; {return x;} int main(void){return 0;}
knr-duplicate-declaration|233|int f(x) int x; int x; {return x;} int main(void){return 0;}
retained-prototype-count|235|int f(int x){return x;} int f(); int main(void){return f();}
strict-void-count|235|int f(void){return 0;} int main(void){return f(1);}
trailing-void|233|int f(int x, void); int main(void){return 0;}
duplicate-typed-name|233|int f(int x, int x); int main(void){return 0;}
function-pointer-extra-depth|231|int main(void){int (**p)(int); return 0;}
parameter-function-adjustment|233|int f(int callback(int)); int main(void){return 0;}
CASES
