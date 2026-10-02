#!/usr/bin/env bash
# Native initializer acceptance/rejection tests; compiles only through Forth.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
"$ROOT/tests/tcc/compile-native.sh" "$ROOT/tests/tcc/native-initializers.c" "$TMP/initializers"
"$TMP/initializers"
reject() {
  local name=$1 expected=$2 source=$3 status=0
  printf '%s\n' "$source" > "$TMP/$name.c"
  "$ROOT/tests/tcc/compile-native.sh" "$TMP/$name.c" "$TMP/$name" > "$TMP/$name.log" 2>&1 || status=$?
  if [[ $status != "$expected" ]]; then
    echo "FAIL $name: expected compiler error $expected, got $status" >&2
    cat "$TMP/$name.log" >&2
    exit 1
  fi
}
reject global_value 219 'int a=1; int b=a; int main(void){return b;}'
reject global_call 219 'int f(void){return 1;} int b=f(); int main(void){return b;}'
reject global_increment 219 'int a; int b=++a; int main(void){return b;}'
reject global_assignment 219 'int a; int b=(a=2); int main(void){return b;}'
reject static_local_read 219 'int main(void){int a=2; static int b=a; return b;}'
reject static_local_address 219 'int main(void){int a; static int *p=&a; return 0;}'
reject static_local_array 219 'int main(void){int a[2]; static int *p=a; return 0;}'
reject static_comma 219 'int a=(1,2); int main(void){return a;}'
reject static_aggregate_copy 219 'struct S{int x;}; struct S a={1}; struct S b=a; int main(void){return b.x;}'
reject missing_braces 225 'int a[2]=1; int main(void){return a[0];}'
reject excess_elements 226 'int a[2]={1,2,3}; int main(void){return a[0];}'
reject excess_characters 223 'char a[2]="abc"; int main(void){return a[0];}'
reject excess_braced_string 223 'char a[3]={"ab","c"}; int main(void){return a[0];}'
reject inferred_empty 220 'int a[]={}; int main(void){return 0;}'
reject inferred_unbraced_struct 222 'struct S{int x;int y;}; struct S a[]={1,2}; int main(void){return a[0].x;}'
reject inferred_unbraced_rows 222 'int a[][2]={1,2,3,4}; int main(void){return a[0][0];}'
echo 'PASS native initializers: runtime values, relocations, zero fill, and rejected nonconstants'
