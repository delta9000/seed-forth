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
bash tests/gcc/sysv-namespaces-check.sh
bash tests/gcc/sysv-abstract-callback-check.sh
bash tests/gcc/sysv-implicit-calls-check.sh
python3 tests/gcc/review-implicit-check.py
bash tests/gcc/sysv-interop-check.sh
bash tests/gcc/sysv-storage-check.sh
python3 tests/gcc/review-storage-probe.py
python3 tests/gcc/constant-check.py
bash tests/gcc/sysv-declaration-types-check.sh
python3 tests/gcc/review-types-check.py
bash tests/gcc/sysv-setjmp-check.sh
python3 tests/gcc/target-macros-check.py
python3 tests/gcc/source-location-check.py
python3 tests/gcc/review-source-location-check.py
python3 tests/gcc/syscall-check.py
python3 tests/gcc/syscall-runtime-check.py
python3 tests/gcc/runtime-check.py
python3 tests/gcc/runtime-oracle-check.py
bash tests/gcc/varargs-intrinsic-check.sh
python3 tests/gcc/varargs-check.py
bash tests/gcc/varargs-interop-check.sh
python3 tests/gcc/stdio-check.py
python3 tests/gcc/stdio-oracle-check.py
python3 tests/gcc/configure-runtime-check.py
python3 tests/gcc/configure-runtime-oracle-check.py
python3 tests/gcc/driver-check.py
python3 tests/gcc/driver-cache-check.py
python3 tests/gcc/review-sysv-check.py
python3 tests/gcc/review-sysv-syscall-check.py
ffs_status=0
bash tests/gcc/sysv-gcc-ffs-check.sh "${GCC4_FFS_SOURCE:-build-out/direct-gcc-inputs/gcc-source/libiberty/ffs.c}" || ffs_status=$?
if [ "$ffs_status" != 0 ] && [ "$ffs_status" != 77 ]; then exit "$ffs_status"; fi
hex_status=0
bash tests/gcc/sysv-gcc-hex-check.sh "${GCC4_HEX_SOURCE:-build-out/direct-gcc-inputs/gcc-source/libiberty/hex.c}" "${GCC4_INCLUDE:-build-out/direct-gcc-inputs/gcc-source/include}" || hex_status=$?
if [ "$hex_status" != 0 ] && [ "$hex_status" != 77 ]; then exit "$hex_status"; fi
tools/tangle.sh verify --strict
echo 'PASS: direct-GCC objects, linker, scalar ABI, typed storage, runtime and driver component gate'
