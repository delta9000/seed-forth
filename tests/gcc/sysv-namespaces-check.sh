#!/usr/bin/env bash
# C ordinary/tag lookup: both declaration orders and scoped ordinary names.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-namespaces.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-compile.sh tests/gcc/sysv-namespaces.c "$work/mapped"
"$work/mapped"
tests/gcc/sysv-object-compile.sh tests/gcc/sysv-namespaces.c "$work/namespace.o"
${CC:-cc} -fno-pie -no-pie "$work/namespace.o" -o "$work/object-check"
"$work/object-check"
${CC:-cc} -std=c90 -pedantic-errors -O2 tests/gcc/sysv-namespaces.c -o "$work/reference"
"$work/reference"
echo 'PASS: independent tag/ordinary/member names in mapped ELF and ET_REL'
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
tag-is-not-value|93|struct missing {int x;}; int f(void){return missing;}
ordinary-function-object-conflict|237|struct same {int x;}; int same(void); int same;
ordinary-prototype-conflict|237|struct same {int x;}; int same(int); int same(long);
CASES
