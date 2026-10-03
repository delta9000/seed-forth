#!/usr/bin/env bash
# Experimental direct-GCC component gate, not a complete GCC bootstrap.
# GCC/ld/readelf are independent interoperability oracles only.
set -euo pipefail
cd "$(dirname "$0")/../.."
for tool in python3 gcc ld readelf; do
    if ! command -v "$tool" >/dev/null; then
        echo "SKIP: component oracle requires $tool" >&2
        exit 77
    fi
done
python3 tests/gcc/object-writer-check.py
python3 tests/gcc/linker-check.py
bash tests/gcc/sysv-check.sh
bash tests/gcc/sysv-interop-check.sh
python3 tests/gcc/syscall-check.py
tools/tangle.sh verify --strict
echo 'PASS: direct-GCC object, linker, scalar ABI and syscall component gate'
