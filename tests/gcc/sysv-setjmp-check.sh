#!/usr/bin/env bash
# Host libc is an oracle for returns-twice behavior, not a bootstrap input.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-setjmp.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-object-compile.sh tests/gcc/sysv-setjmp.c "$work/forth.o"
for optimization in -O0 -O2; do
  ${CC:-cc} -std=c11 "$optimization" -Wall -Wextra -fno-builtin -fno-pie -no-pie \
    tests/gcc/sysv-setjmp-host.c tests/gcc/sysv-setjmp-guard.S "$work/forth.o" -o "$work/check"
  timeout 10 "$work/check"
  ${CC:-cc} -std=c11 "$optimization" -Wall -Wextra -fno-builtin -fno-pie -no-pie \
    tests/gcc/sysv-setjmp-host.c tests/gcc/sysv-setjmp-guard.S tests/gcc/sysv-setjmp.c -o "$work/reference"
  timeout 10 "$work/reference"
done
