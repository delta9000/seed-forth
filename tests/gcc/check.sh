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
python3 tests/gcc/archive-boundary-check.py
python3 tests/gcc/review-archive-check.py
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
bash tests/gcc/sysv-declarator-edges-check.sh
python3 tests/gcc/review-declarator-check.py
SF_GCC_CAST_ORACLE=1 bash tests/gcc/sysv-function-integer-casts-check.sh
bash tests/gcc/sysv-binary64-check.sh
python3 tests/gcc/float-literal-check.py
python3 tests/gcc/review-floating-literals.py
bash tests/gcc/sysv-setjmp-check.sh
python3 tests/gcc/target-macros-check.py
python3 tests/gcc/source-location-check.py
python3 tests/gcc/review-source-location-check.py
python3 tests/gcc/computed-include-check.py
python3 tests/gcc/review-computed-include-check.py
python3 tests/gcc/literal-splice-check.py
python3 tests/gcc/review-literal-splice-check.py
python3 tests/gcc/syscall-check.py
python3 tests/gcc/syscall-runtime-check.py
python3 tests/gcc/runtime-check.py
python3 tests/gcc/runtime-oracle-check.py
sort_work=$(mktemp -d "$PWD/build-out/sort-composed-XXXXXX")
python3 tests/gcc/sort-check.py --work "$sort_work"
python3 tests/gcc/sort-oracle-check.py "$sort_work"
bash tests/gcc/varargs-intrinsic-check.sh
python3 tests/gcc/varargs-check.py
bash tests/gcc/varargs-interop-check.sh
python3 tests/gcc/varargs-binary64-check.py
python3 tests/gcc/stdio-check.py
python3 tests/gcc/stdio-oracle-check.py
python3 tests/gcc/configure-runtime-check.py
python3 tests/gcc/configure-runtime-oracle-check.py
python3 tests/gcc/abort-check.py
python3 tests/gcc/ctype-assert-check.py
python3 tests/gcc/frame-check.py
python3 tests/gcc/driver-check.py
python3 tests/gcc/driver-cache-check.py
python3 tests/gcc/driver-archive-check.py
python3 tests/gcc/review-sysv-check.py
python3 tests/gcc/review-sysv-syscall-check.py
ffs_status=0
bash tests/gcc/sysv-gcc-ffs-check.sh "${GCC4_FFS_SOURCE:-build-out/direct-gcc-inputs/gcc-source/libiberty/ffs.c}" || ffs_status=$?
if [ "$ffs_status" != 0 ] && [ "$ffs_status" != 77 ]; then exit "$ffs_status"; fi
hex_status=0
bash tests/gcc/sysv-gcc-hex-check.sh "${GCC4_HEX_SOURCE:-build-out/direct-gcc-inputs/gcc-source/libiberty/hex.c}" "${GCC4_INCLUDE:-build-out/direct-gcc-inputs/gcc-source/include}" || hex_status=$?
if [ "$hex_status" != 0 ] && [ "$hex_status" != 77 ]; then exit "$hex_status"; fi
gcc_source=${GCC4_SOURCE_ROOT:-build-out/direct-gcc-inputs/gcc-source}
if [ -f "$gcc_source/libiberty/hashtab.c" ]; then
    python3 tests/gcc/review-floating-check.py --source-root "$gcc_source"
    python3 tests/gcc/bitfield-check.py --source-root "$gcc_source" --oracle
    python3 tests/gcc/review-bitfield-check.py --source-root "$gcc_source"
    bash tests/gcc/sysv-gcc-obstack-check.sh "$gcc_source/libiberty/obstack.c" "$gcc_source/include"
else
    python3 tests/gcc/review-floating-check.py --skip-hashtab
    echo 'SKIP: original GCC hashtab, fibheap and obstack gates require the pinned source archive' >&2
fi
tools/tangle.sh verify --strict
echo 'PASS: direct-GCC objects, archives, ABI, typed storage, floating literals, preprocessor, runtime and driver component gate'
