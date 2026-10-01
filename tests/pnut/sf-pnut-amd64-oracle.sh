#!/usr/bin/env bash
# Verification-only GCC oracle, deliberately outside the seed-built chain.
# Requires the completed amd64 build tree as $1; never builds chain artifacts.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
W=$1
SF_PNUT64_GCC_ORACLE=1
me=sf-pnut-amd64-oracle
fail() { echo "$me: FAIL: $1" >&2; exit 1; }
sha() { sha256sum < "$1" | cut -d' ' -f1; }
X=(-Dtarget_x86_64_linux -DONE_PASS_GENERATOR)
KIT_OPTS=("${X[@]}" -DUNDEFINED_LABELS_ARE_RUNTIME_ERRORS -DENABLE_PNUT_INLINE_INTERRUPT -DNO_BUILTIN_LIBC)
cd "$W/kit"
TCC_PNUT_FLAGS=(-D BOOTSTRAP=1 -D HAVE_LONG_LONG=1 -D TCC_TARGET_X86_64=1
    -D 'CONFIG_SYSROOT="/"' -D 'CONFIG_TCC_CRTPREFIX="build/boot0-lib"'
    -D 'CONFIG_TCC_ELFINTERP="/mes/loader"' -D 'CONFIG_TCC_SYSINCLUDEPATHS="libc64/include"'
    -D 'TCC_LIBGCC="build/boot0-lib/libc.a"' -D CONFIG_TCC_LIBTCC1_MES=0 -D CONFIG_TCCBOOT=1
    -D CONFIG_TCC_STATIC=1 -D CONFIG_USE_LIBGCC=1 -D 'TCC_VERSION="0.9.27"' -D ONE_SOURCE=1
    -D 'CONFIG_TCCDIR="build/boot0-lib/tcc"')
go() {
    local cc=$1 new=$2 lib=build/${3:-$2}-lib out sysinc
    ./bintools mkdir -p "$lib/tcc"
    $cc -c libc64/src/crt1.c -o "$lib/crt1.o"
    printf "" > "$lib/crtn.o"
    printf "" > "$lib/crti.o"
    $cc -c -D ADD_LIBC_STUB -I libc64/include -o "$lib/libc.o" libc64/libc.c
    $cc -ar cr "$lib/libc.a" "$lib/libc.o"
    $cc -c -o "$lib/libtcc1.o" kit/libtcc1.c
    $cc -c -o "$lib/va_list.o" tcc-0.9.27/lib/va_list.c
    $cc -ar cr "$lib/tcc/libtcc1.a" "$lib/libtcc1.o" "$lib/va_list.o"
    for out in "-o build/tcc-$new" "-c -o build/tcc-$new.o"; do
        case $out in -c*) sysinc=SOME_DIRECTORY ;; *) sysinc=libc64/include ;; esac
        # shellcheck disable=SC2086
        $cc -static $out \
            -D BOOTSTRAP=1 -D __SIZEOF_LONG_LONG__=8 -D HAVE_FLOAT=1 -D HAVE_BITFIELD=1 \
            -D HAVE_LONG_LONG=1 -D HAVE_SETJMP=1 -I libc64/include -D TCC_TARGET_X86_64=1 \
            -D "CONFIG_TCCDIR=\"$lib/tcc\"" -D "CONFIG_TCC_CRTPREFIX=\"$lib\"" \
            -D "CONFIG_TCC_LIBPATHS=\"$lib:$lib/tcc\"" -D "CONFIG_TCC_SYSINCLUDEPATHS=\"$sysinc\"" \
            -D "TCC_LIBGCC=\"$lib/libc.a\"" -D 'TCC_LIBTCC1="libtcc1.a"' \
            -D 'CONFIG_TCC_ELFINTERP="/mes/loader"' -D CONFIG_TCCBOOT=1 -D CONFIG_TCC_STATIC=1 \
            -D CONFIG_USE_LIBGCC=1 -D 'TCC_VERSION="0.9.27"' -D ONE_SOURCE=1 -L "$lib" \
            tcc-0.9.27/tcc.c
    done
}
if [ "${SF_PNUT64_GCC_ORACLE:-0}" = 1 ]; then
    command -v gcc >/dev/null || fail "SF_PNUT64_GCC_ORACLE=1 needs gcc"
    O=$W/oracle; mkdir -p "$O"
    (cd "$W/pnut" && gcc -w -O1 "${X[@]}" pnut.c -o "$O/pnut-gcc") > "$O/pnut-gcc.log" 2>&1 \
        || fail "gcc could not build pnut (see $O/pnut-gcc.log)"
    "$O/pnut-gcc" pnut.c "${KIT_OPTS[@]}" -o "$O/pnut-exe" > "$O/pnut-exe.log" 2>&1 \
        || fail "gcc-built pnut could not build pnut-exe (see $O/pnut-exe.log)"
    (cd "$W/pnut" && "$O/pnut-gcc" pnut.c "${X[@]}" -o "$O/pnut64-g2") > "$O/pnut64-g2.log" 2>&1 \
        || fail "gcc-built pnut could not build pnut64-g2 (see $O/pnut64-g2.log)"
    cmp pnut-exe "$O/pnut-exe" || fail "reference: gcc-built pnut builds a different pnut-exe"
    cmp "$W/pnut64-g2" "$O/pnut64-g2" || fail "reference: gcc-built pnut builds a different pnut64-g2"
    echo "$me: reference: gcc-built pnut builds the same pnut64-g2 ($(sha "$W/pnut64-g2" | cut -c1-16)...) and pnut-exe ($(sha pnut-exe | cut -c1-16)...)"
    # A second kit tree, seeded by a gcc-built tcc instead of tcc-pnut.
    G=$W/kit-gcc; mkdir -p "$G/build"
    cp -r tcc-0.9.27 libc64 kit bintools "$G/"
    (
        cd "$G"
        gcc -w -O1 "${TCC_PNUT_FLAGS[@]}" tcc-0.9.27/tcc.c -o build/tcc-gcc
        go build/tcc-gcc boot0; go build/tcc-boot0 boot1; go build/tcc-boot1 boot2
    ) > "$O/kit-gcc.log" 2>&1 || fail "reference: gcc-seeded tcc chain (see $O/kit-gcc.log)"
    for f in tcc-boot2 boot2-lib/crt1.o boot2-lib/libc.a boot2-lib/tcc/libtcc1.a; do
        cmp "build/$f" "$G/build/$f" || fail "reference: gcc-seeded $f differs from the pnut-seeded one"
    done
    echo "$me: reference: a gcc-built tcc-0.9.27 seeds the same tcc-boot2 ($(sha build/tcc-boot2 | cut -c1-16)...) and boot2 crt1.o/libc.a/libtcc1.a"
fi

echo "$me: PASS (GCC references agree)"
