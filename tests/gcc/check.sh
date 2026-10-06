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
python3 tests/gcc/symbol-capacity-check.py
python3 tests/gcc/arena-capacity-check.py
python3 tests/gcc/workspace-capacity-check.py
python3 tests/gcc/object-capacity-check.py
python3 tests/gcc/source-capacity-check.py
python3 tests/gcc/workspace-label-check.py
python3 tests/gcc/object-writer-check.py
python3 tests/gcc/linker-check.py
python3 tests/gcc/linker-c-check.py
python3 tests/gcc/archive-boundary-check.py
python3 tests/gcc/review-archive-check.py
bash tests/gcc/sysv-check.sh
bash tests/gcc/sysv-knr-check.sh
python3 tests/gcc/parameter-storage-check.py
python3 tests/gcc/function-parameter-check.py
python3 tests/gcc/nested-function-pointer-check.py
python3 tests/gcc/grouped-declarator-check.py
python3 tests/gcc/block-function-decl-check.py
python3 tests/gcc/function-typedef-check.py
python3 tests/gcc/function-object-cast-check.py
python3 tests/gcc/grouped-pointer-type-check.py
bash tests/gcc/sysv-namespaces-check.sh
bash tests/gcc/sysv-abstract-callback-check.sh
bash tests/gcc/sysv-implicit-calls-check.sh
python3 tests/gcc/review-implicit-check.py
bash tests/gcc/sysv-interop-check.sh
bash tests/gcc/sysv-storage-check.sh
python3 tests/gcc/review-storage-probe.py
python3 tests/gcc/constant-check.py
python3 tests/gcc/shift-constants-check.py
python3 tests/gcc/array-pointer-check.py
python3 tests/gcc/multidimensional-record-check.py
python3 tests/gcc/large-record-check.py
python3 tests/gcc/sizeof-postfix-check.py
python3 tests/gcc/ranked-arrays-check.py
python3 tests/gcc/pointer-array-qualifiers-check.py
python3 tests/gcc/qualifier-order-check.py
python3 tests/gcc/qualified-array-check.py
python3 tests/gcc/constant-address-check.py
bash tests/gcc/sysv-declaration-types-check.sh
python3 tests/gcc/review-types-check.py
bash tests/gcc/sysv-declarator-edges-check.sh
python3 tests/gcc/review-declarator-check.py
SF_GCC_CAST_ORACLE=1 bash tests/gcc/sysv-function-integer-casts-check.sh
python3 tests/gcc/aggregate-check.py --oracle
python3 tests/gcc/knr-record-check.py
python3 tests/gcc/record-varargs-check.py
knr_source=${GCC4_SOURCE_ROOT:-build-out/direct-gcc-inputs/gcc-source}
if [ -f "$knr_source/libiberty/regex.c" ] && [ -n "${GCC4_LIBIBERTY_CONFIG:-}" ]; then
    python3 tests/gcc/knr-regex-check.py --source-root "$knr_source" --config-dir "$GCC4_LIBIBERTY_CONFIG"
else
    echo 'SKIP: original regex raw/explicit-malloc-mode proof requires pinned source and genuine libiberty config'
fi
expression_source=${GCC4_SOURCE_ROOT:-build-out/direct-gcc-inputs/gcc-source}
if [ -f "$expression_source/libcpp/charset.c" ]; then
    python3 tests/gcc/libcpp-expression-check.py --source-root "$expression_source"
else
    python3 tests/gcc/libcpp-expression-check.py
    echo 'SKIP: original-derived libcpp expression checks require the pinned source archive'
fi
python3 tests/gcc/binary64-arguments-check.py
python3 tests/gcc/long-double-check.py
python3 tests/gcc/binary32-values-check.py
python3 tests/gcc/conditional-values-check.py
python3 tests/gcc/long-long-check.py
python3 tests/gcc/bool-check.py
python3 tests/gcc/if-unsigned-check.py
python3 tests/gcc/switch-labels-check.py
python3 tests/gcc/conditional-qualified-null-check.py
bash tests/gcc/sysv-binary64-check.sh
python3 tests/gcc/float-literal-check.py
python3 tests/gcc/review-floating-literals.py
python3 tests/gcc/static-float-check.py
bash tests/gcc/sysv-setjmp-check.sh
python3 tests/gcc/nonlocal-runtime-check.py --oracle
python3 tests/gcc/review-nonlocal-check.py
python3 tests/gcc/target-macros-check.py
python3 tests/gcc/source-location-check.py
python3 tests/gcc/review-source-location-check.py
python3 tests/gcc/line-control-check.py
python3 tests/gcc/macro-parameter-splices-check.py
python3 tests/gcc/macro-suppression-check.py
python3 tests/gcc/macro-suppression-shadow-check.py
line_include=${GCC4_INCLUDE:-${GCC4_SOURCE_ROOT:-build-out/direct-gcc-inputs/gcc-source}/include}
if [ -f "$line_include/ansidecl.h" ]; then
    python3 tests/gcc/line-control-ansi-check.py --include "$line_include"
else
    echo 'SKIP: unchanged GCC ansidecl.h proof requires the pinned source archive' >&2
fi
python3 tests/gcc/computed-include-check.py
python3 tests/gcc/review-computed-include-check.py
python3 tests/gcc/literal-splice-check.py
python3 tests/gcc/file-splice-check.py
python3 tests/gcc/review-literal-splice-check.py
python3 tests/gcc/syscall-check.py
python3 tests/gcc/syscall-runtime-check.py
python3 tests/gcc/runtime-check.py
python3 tests/gcc/runtime-oracle-check.py
python3 tests/gcc/strcspn-check.py
python3 tests/gcc/measured-runtime-supervisor-check.py
python3 tests/gcc/measured-runtime-check.py
python3 tests/gcc/directory-buffering-check.py
sort_work=$(mktemp -d "$PWD/build-out/sort-composed-XXXXXX")
python3 tests/gcc/sort-check.py --work "$sort_work"
python3 tests/gcc/sort-oracle-check.py "$sort_work"
python3 tests/gcc/search-error-check.py
python3 tests/gcc/strtol-check.py
bash tests/gcc/varargs-intrinsic-check.sh
python3 tests/gcc/varargs-check.py
bash tests/gcc/varargs-interop-check.sh
python3 tests/gcc/varargs-binary64-check.py
python3 tests/gcc/review-binary64-va-arg-check.py
python3 tests/gcc/stdio-check.py
python3 tests/gcc/stdio-oracle-check.py
python3 tests/gcc/startup-check.py
python3 tests/gcc/descriptor-check.py
python3 tests/gcc/descriptor-io-check.py
python3 tests/gcc/fcntl-check.py
python3 tests/gcc/stdint-check.py
python3 tests/gcc/process-api-check.py
python3 tests/gcc/driver-runtime-check.py
python3 tests/gcc/binutils-runtime-check.py
python3 tests/gcc/procfs-time-check.py
python3 tests/gcc/mapping-check.py
python3 tests/gcc/dirent-check.py
python3 tests/gcc/write-check.py
python3 tests/gcc/environment-locale-check.py
calendar_source=${GCC4_SOURCE_ROOT:-build-out/direct-gcc-inputs/gcc-source}
if [ -f "$calendar_source/libcpp/macro.c" ]; then
    TZ=UTC0 python3 tests/gcc/calendar-check.py --gcc-source "$calendar_source"
else
    TZ=UTC0 python3 tests/gcc/calendar-check.py
    echo 'SKIP: original libcpp calendar formatting checks require the pinned source archive'
fi
python3 tests/gcc/wide-check.py
python3 tests/gcc/wide-stdio-check.py
python3 tests/gcc/ctype-lex-check.py
python3 tests/gcc/float-header-check.py
python3 tests/gcc/math-link-check.py
math_log=$(mktemp "$PWD/build-out/math-check-XXXXXX.log")
python3 tests/gcc/math-check.py | tee "$math_log"
math_report=$(sed -n '2p' "$math_log")
python3 tests/gcc/math-oracle-check.py --production-output "${math_report%/*}/results.txt"
python3 tests/gcc/bufsiz-check.py
python3 tests/gcc/stream-flex-check.py
python3 tests/gcc/stream-flex-fault-check.py
python3 tests/gcc/isatty-check.py
python3 tests/gcc/integer-input-check.py
python3 tests/gcc/scanf-percent-check.py
python3 tests/gcc/configure-runtime-check.py
python3 tests/gcc/configure-runtime-oracle-check.py
python3 tests/gcc/abort-check.py
python3 tests/gcc/ctype-assert-check.py
python3 tests/gcc/strtoul-check.py
python3 tests/gcc/atol-check.py
bash tests/gcc/abs-check.sh
python3 tests/gcc/signal-check.py
python3 tests/gcc/getopt-check.py
python3 tests/gcc/frame-check.py
python3 tests/gcc/driver-check.py
python3 tests/gcc/driver-cache-check.py
python3 tests/gcc/driver-archive-check.py
python3 tests/gcc/driver-libsearch-check.py
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
    if [ -n "${GCC4_LIBIBERTY_CONFIG:-}" ]; then
        python3 tests/gcc/varargs-vasprintf-check.py --source-root "$gcc_source" --config-dir "$GCC4_LIBIBERTY_CONFIG"
    else
        echo 'SKIP: original vasprintf execution additionally needs GCC4_LIBIBERTY_CONFIG from genuine configure probes' >&2
    fi
else
    python3 tests/gcc/review-floating-check.py --skip-hashtab
    echo 'SKIP: original GCC hashtab, fibheap and obstack gates require the pinned source archive' >&2
fi
lexers_status=0
python3 tests/gcc/lexers-check.py || lexers_status=$?
if [ "$lexers_status" != 0 ] && [ "$lexers_status" != 77 ]; then exit "$lexers_status"; fi
e2e_status=0
python3 tests/gcc/e2e-freestanding-check.py || e2e_status=$?
if [ "$e2e_status" != 0 ] && [ "$e2e_status" != 77 ]; then exit "$e2e_status"; fi
tools/tangle.sh verify --strict
echo 'PASS: direct-GCC objects, archives, ABI, typed storage, floating literals, preprocessor, runtime and driver component gate'
