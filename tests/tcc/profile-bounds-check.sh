#!/usr/bin/env bash
# Unsupported native call/float forms must reject, rather than emit wrong code.
set -euo pipefail
cd "$(dirname "$0")/../.."
WORK=$(mktemp -d "$PWD/build-out/profile-bounds.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
reject() {
  local name=$1 code=$2 source=$3 status=0
  printf '%s\n' "$source" >"$WORK/$name.c"
  tests/tcc/compile-native.sh "$WORK/$name.c" "$WORK/$name" >"$WORK/$name.log" 2>&1 || status=$?
  if [ "$status" != "$code" ] || [ -e "$WORK/$name" ]; then
    cat "$WORK/$name.log" >&2
    echo "FAIL: $name expected error $code and no executable, got $status" >&2
    exit 1
  fi
}
reject aggregate-parameter 212 'struct S { long a, b; }; long sum(struct S s) { return s.a+s.b; } int main(void) { struct S s={41,42}; return sum(s)!=83; }'
reject aggregate-return 212 'struct S { long a; }; struct S make(void); int main(void) { return 0; }'
reject aggregate-argument 212 'struct S { long a; }; int consume(); int main(void) { struct S s={1}; return consume(s); }'
reject aggregate-indirect 212 'struct S { long a; }; int consume(int x) { return x; } int main(void) { int (*f)()=consume; struct S s={1}; return f(s); }'
reject float-arithmetic 214 'int main(void) { float x=3, y=2, z=x/y; return (int)(z*2)!=3; }'
reject double-cast 214 'int main(void) { return (int)(double)3; }'
reject long-double-member 214 'struct S { long double value; }; int main(void) { return 0; }'
reject float-parameter 214 'int consume(float x); int main(void) { return 0; }'
reject float-function-pointer 214 'int (*consume)(float x); int main(void) { return 0; }'
cat >"$WORK/seed-bits.c" <<'SOURCE'
int main(void) {
    float f=3;
    double d=2;
    long double l=4;
    return sizeof(f)!=8 || sizeof(d)!=8 || sizeof(l)!=8 || (long)(f+d*l)!=11;
}
SOURCE
SF_NATIVE_FLOATBITS=1 tests/tcc/compile-native.sh "$WORK/seed-bits.c" "$WORK/seed-bits"
"$WORK/seed-bits"
echo 'PASS: nine unsupported native forms reject; explicit seed-only float bit transport preserved'
