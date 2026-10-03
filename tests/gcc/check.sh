#!/usr/bin/env bash
# Experimental direct-GCC component gate, not a complete GCC bootstrap.
# GCC/ld/readelf are independent interoperability oracles only.
set -euo pipefail
cd "$(dirname "$0")/../.."
for tool in python3 gcc ld readelf objdump; do
    if ! command -v "$tool" >/dev/null; then
        echo "SKIP: component oracle requires $tool" >&2
        exit 77
    fi
done
python3 tests/gcc/object-writer-check.py
python3 tests/gcc/linker-check.py
python3 tests/gcc/linker-c-check.py
bash tests/gcc/sysv-check.sh
bash tests/gcc/sysv-knr-check.sh
bash tests/gcc/sysv-interop-check.sh
python3 tests/gcc/syscall-check.py
python3 tests/gcc/syscall-runtime-check.py
python3 tests/gcc/runtime-check.py
python3 tests/gcc/runtime-oracle-check.py
python3 tests/gcc/review-sysv-check.py
python3 tests/gcc/review-sysv-syscall-check.py
ffs_status=0
bash tests/gcc/sysv-gcc-ffs-check.sh "${GCC4_FFS_SOURCE:-build-out/direct-gcc-inputs/gcc-source/libiberty/ffs.c}" || ffs_status=$?
if [ "$ffs_status" != 0 ] && [ "$ffs_status" != 77 ]; then exit "$ffs_status"; fi
tools/tangle.sh verify --strict
echo 'PASS: direct-GCC object, linker, scalar ABI and syscall component gate'
