#!/usr/bin/env bash
# Production compilation/linking is entirely Forth; host ABI oracles opt in.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-function-integers.XXXXXX)
trap 'rm -rf "$work"' EXIT
fixture=tests/gcc/sysv-function-integer-casts.c
tests/gcc/sysv-compile.sh "$fixture" "$work/mapped"
"$work/mapped"
python3 tools/gcc-direct-cc.py "$fixture" -o "$work/linked"
"$work/linked"
echo 'PASS: integer/function-pointer representations, static sentinels, source normalization and restored typed calls in Forth-only ELF/object paths'
while IFS='|' read -r label source; do
  printf '%s\n' "$source" > "$work/reject.c"
  for mode in mapped object; do
    printf 'previous artifact\n' > "$work/reject.out"
    rc=0
    if [ "$mode" = mapped ]; then
      tests/gcc/sysv-compile.sh "$work/reject.c" "$work/reject.out" >"$work/reject.log" 2>&1 || rc=$?
    else
      tests/gcc/sysv-object-compile.sh "$work/reject.c" "$work/reject.out" >"$work/reject.log" 2>&1 || rc=$?
    fi
    if [ "$rc" != 230 ] || [ "$(cat "$work/reject.out")" != 'previous artifact' ]; then
      cat "$work/reject.log" >&2
      echo "FAIL: $label/$mode returned $rc, expected 230 with preserved output" >&2
      exit 1
    fi
  done
  echo "PASS: $label rejects in both output paths and preserves output"
done <<'CASES'
runtime-function-to-int|int f(void); int g(void){return (int)f;}
runtime-function-to-uint|int f(void); unsigned int g(void){return (unsigned int)f;}
runtime-function-to-short|int f(void); short g(void){return (short)f;}
runtime-function-to-char|int f(void); char g(void){return (char)f;}
runtime-function-to-object|int f(void); void *g(void){return (void *)f;}
runtime-object-to-function|int g(void *p){return ((int (*)(void))p)();}
runtime-null-object-to-function|typedef void (*H)(int); H g(void){return (H)(void *)0;}
runtime-function-to-function-pointer-object|typedef int (*F)(void); int f(void); F *g(void){return (F *)f;}
static-function-to-int|int f(void); int p=(int)f; int main(void){return 0;}
static-function-to-object|int f(void); void *p=(void *)f; int main(void){return 0;}
static-object-to-function|int x; int (*p)(void)=(int (*)(void))&x; int main(void){return 0;}
static-null-object-to-function|typedef void (*H)(int); H p=(H)(void *)0; int main(void){return 0;}
static-function-to-function-pointer-object|typedef int (*F)(void); int f(void); F *p=(F *)f; int main(void){return 0;}
CASES
# The ordinary pointer-to-pointer signature round-trip gate stays unchanged
# apart from removing the three newly supported integer/null rejections.
bash tests/gcc/sysv-function-pointer-casts-check.sh
if [ "${SF_GCC_CAST_ORACLE:-0}" = 1 ]; then
  python3 tools/gcc-direct-cc.py -DSF_FUNCTION_INTEGER_NO_MAIN -c "$fixture" -o "$work/fixture.o"
  for optimization in 0 2; do
    "${CC:-cc}" -std=c90 -pedantic-errors -Wno-int-to-pointer-cast -O"$optimization" "$fixture" -o "$work/host-O$optimization"
    "$work/host-O$optimization"
    "${CC:-cc}" -std=c90 -pedantic-errors -O"$optimization" -fno-pie -no-pie \
      tests/gcc/sysv-function-integer-casts-peer.c "$work/fixture.o" -o "$work/peer-O$optimization"
    "$work/peer-O$optimization"
  done
  echo 'PASS: separate host O0/O2 semantic and cross-compiler ABI oracles'
fi
