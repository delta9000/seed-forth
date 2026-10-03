#!/usr/bin/env bash
# Independent host GCC/libc interoperability; never a production input.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-varargs-interop.XXXXXX)
trap 'rm -rf "$work"' EXIT
for source in provider interop forwarding; do
    tests/gcc/sysv-object-compile.sh "tests/gcc/varargs-$source.c" "$work/$source.o" \
        runtime/gcc-seed/include tests/gcc
done
for optimization in 0 2; do
    "${CC:-gcc}" -std=c99 -O"$optimization" -Wall -Wextra -Werror -fno-pie -no-pie \
        tests/gcc/varargs-oracle.c tests/gcc/varargs-forwarding-oracle.c \
        tests/gcc/varargs-al-oracle.S \
        "$work/provider.o" "$work/interop.o" "$work/forwarding.o" \
        -o "$work/check-O$optimization"
    "$work/check-O$optimization"
done
printf '%s\n' 'PASS: GP varargs and opaque floating-list forwarding at -O0 and -O2'
