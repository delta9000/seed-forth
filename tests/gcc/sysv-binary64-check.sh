#!/usr/bin/env bash
# Production proof uses only Forth-generated compiler, runtime and linker bytes.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-binary64.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-compile.sh tests/gcc/sysv-binary64.c "$work/mapped"
"$work/mapped"
python3 tools/gcc-direct-cc.py tests/gcc/sysv-binary64.c -o "$work/linked"
"$work/linked"
echo 'PASS: binary64 literals, expressions, payloads and return ABI through Forth-only ELF/object paths'
while IFS='|' read -r name source; do
  printf '%s\n' "$source" > "$work/reject.c"
  printf 'previous artifact\n' > "$work/reject.o"
  rc=0
  tests/gcc/sysv-object-compile.sh "$work/reject.c" "$work/reject.o" >"$work/reject.log" 2>&1 || rc=$?
  if [ "$rc" != 232 ] || [ "$(cat "$work/reject.o")" != 'previous artifact' ]; then
    cat "$work/reject.log" >&2
    echo "FAIL: $name returned $rc, expected232 and preserved output" >&2; exit 1
  fi
  echo "PASS: $name rejects with232 and preserves output"
done <<'CASES'
static-double|double x=0.0;
increment-double|double f(double *p){return ++*p;}
floating-index|int f(int *p,double *q){return p[*q];}
floating-switch|int f(double *p){switch(*p){case 0:return 1;}return 0;}
integer-shift-by-double|int f(double *p){return 1 << *p;}
CASES
