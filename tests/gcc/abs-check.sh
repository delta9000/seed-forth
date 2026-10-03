#!/usr/bin/env bash
# Forth production proof plus independent host callers. INT_MIN is undefined.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-abs.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 tools/gcc-direct-cc.py tests/gcc/abs.c -o "$work/forth"
"$work/forth"
tests/gcc/sysv-object-compile.sh runtime/gcc-seed/abs.c "$work/abs.o" runtime/gcc-seed/include
for opt in 0 2; do
    gcc -std=c90 -O"$opt" -fno-builtin -fno-pie -no-pie \
        tests/gcc/abs.c "$work/abs.o" -o "$work/oracle-O$opt"
    "$work/oracle-O$opt"
done
echo 'PASS: abs representable-int domain, Forth-only and host callers O0/O2'
