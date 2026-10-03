#!/usr/bin/env bash
# Isolate intrinsic lowering with a genuine record-array declaration.
# The full stdarg alias, ELF-object, and interop gates are separate tests.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-varargs-intrinsic.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-compile.sh tests/gcc/varargs-intrinsic-smoke.c "$work/check"
"$work/check"
printf '%s\n' 'PASS: System V intrinsic register/stack traversal and va_copy'
