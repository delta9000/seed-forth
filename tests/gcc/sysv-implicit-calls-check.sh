#!/usr/bin/env bash
# C90 implicit calls: scoped names, persistent fixups and honest link failures.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-implicit-calls.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-compile.sh tests/gcc/sysv-implicit-calls.c "$work/mapped"
"$work/mapped"
tests/gcc/sysv-object-compile.sh tests/gcc/sysv-implicit-calls.c "$work/fixture.o"
${CC:-cc} -fno-pie -no-pie "$work/fixture.o" -o "$work/object-check"
"$work/object-check"
${CC:-cc} -std=c90 -pedantic-errors -Wno-implicit-function-declaration -O2 \
  tests/gcc/sysv-implicit-calls.c -o "$work/reference"
"$work/reference"
echo 'PASS: C90 implicit calls and function addresses survive parser scopes'
cat > "$work/unresolved.c" <<'SOURCE'
struct missing {int x;}; int main(void){{missing(1);} {missing(2);} return missing(3);}
SOURCE
tests/gcc/sysv-object-compile.sh "$work/unresolved.c" "$work/unresolved.o"
readelf -r "$work/unresolved.o" > "$work/relocations"
[ "$(rg -c 'R_X86_64_PLT32.*missing' "$work/relocations")" = 3 ]
if ${CC:-cc} -fno-pie -no-pie "$work/unresolved.o" -o "$work/bad-link" >"$work/link.log" 2>&1; then
  echo 'FAIL: unknown external unexpectedly linked' >&2; exit 1
fi
echo 'PASS: unresolved implicit external retains all relocations and fails final link'
while IFS='|' read -r label code source; do
  printf '%s\n' "$source" > "$work/reject.c"
  printf 'previous artifact\n' > "$work/reject.o"
  rc=0
  tests/gcc/sysv-object-compile.sh "$work/reject.c" "$work/reject.o" >"$work/reject.log" 2>&1 || rc=$?
  if [ "$rc" != "$code" ] || [ "$(cat "$work/reject.o")" != 'previous artifact' ]; then
    cat "$work/reject.log" >&2
    echo "FAIL: $label returned $rc, expected $code with preserved output" >&2; exit 1
  fi
  echo "PASS: $label rejects with $code and preserves output"
done <<'CASES'
return-conflict|237|int a(void){return f();} long f(void){return 0;}
promotion-conflict|237|int a(void){return f(1);} int f(char x){return x;}
static-linkage-conflict|237|int a(void){return f();} static int f(void){return 0;}
object-conflict|237|int a(void){return f();} int f;
scope-ended|93|int a(void){{f();} return (long)f;}
unknown-object|93|int a(void){return missing;}
known-local-not-function|230|int a(void){int f; f=1; return f();}
CASES
rc=0
tests/gcc/sysv-compile.sh "$work/unresolved.c" "$work/unresolved" >"$work/reject.log" 2>&1 || rc=$?
[ "$rc" = 206 ] || { cat "$work/reject.log" >&2; exit 1; }
echo 'PASS: standalone ELF rejects unresolved implicit calls with206'
