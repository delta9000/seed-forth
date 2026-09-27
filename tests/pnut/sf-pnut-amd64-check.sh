#!/usr/bin/env bash
# sf-pnut-amd64-check.sh — seed-forth to TinyCC on amd64 alone ("route 2").
#
# The same climb as sf-pnut-check.sh, with every program an x86-64 ELF, so no
# IA-32 emulation is needed anywhere and no gcc is on the path:
#
#   seed-forth -> SF-built pnut (amd64) -> pnut-exe -> pnut-exe-for-tcc
#              -> tcc-pnut (tcc-0.9.27, TCC_TARGET_X86_64)
#              -> tcc-boot0 -> tcc-boot1 -> tcc-boot2 = tcc-boot3
#
# Stage 1.  SF (010-lib.fth + [0-9][0-9][0-9]-cc-*.fth) compiles
#           vendor/pnut/pnut.c (abc34a5) unmodified, with
#           `#define target_x86_64_linux 1` and `#define ONE_PASS_GENERATOR 1`
#           in front -> sf-pnut64, an amd64 pnut that emits amd64 code.
# Stage 2.  Self-hosting: sf-pnut64 -> pnut64-g2 -> pnut64-g3, g2 == g3.
# Stage 3.  sf-pnut64 builds pnut-exe with pnut's TCC-kit options for
#           x86_64 (kit/bootstrap.sh's PNUT_EXE_TCC_OPTIONS less
#           SUPPORT_EMULATED_INT64, which is i386-only); pnut-exe builds the
#           kit's bintools.
# Stage 4.  bintools unpack pnut's vendored tcc-0.9.27 tarball (sha256
#           checked first) and apply the kit's 8 patches (kit/tcc-patches);
#           then patches/amd64/tcc/*.diff; libc64 = portable_libc plus
#           patches/amd64/libc/*.diff.
# Stage 5.  pnut-exe builds pnut-exe-for-tcc from pnut.c plus
#           patches/amd64/pnut/01-heap-size.diff, without ONE_PASS_GENERATOR
#           (its 1,000,000-byte output cap is below tcc-pnut's size).
# Stage 6.  pnut-exe-for-tcc compiles tcc.c -> tcc-pnut; then tcc-boot0..3
#           exactly as kit/bootstrap.sh's go(), for x86_64 and libc64, with
#           tcc-0.9.27/lib/va_list.c added to libtcc1.a.  tcc-boot2 and
#           tcc-boot3 must be byte-identical, and so must their .o files.
# Stage 7.  tcc-boot2 builds and runs tests/pnut/amd64/{t64,hello,printf}.c
#           and portable_libc's own test-libc.c; pnut-exe builds printf.c
#           with libc64 too (pnut's side of the same libc); and tcc-boot2
#           builds pnut.c into a pnut that rebuilds pnut64-g2 byte for byte.
#
# Every stage's output is checked against the sha256 pinned below
# (REPRODUCIBLE.md, "amd64 route").  After a deliberate change to a patch,
# SF_PNUT64_REPIN=1 prints the new values instead of failing on them.
#
# SF_PNUT64_GCC_ORACLE=1 adds a REFERENCE COMPARISON after the chain
# (./verify.sh sets it; the chain itself never runs gcc): a gcc-built pnut
# with stage 1's flags must build the same pnut-exe as sf-pnut64, and a
# gcc-built tcc (same patched sources, same -D flags as tcc-pnut, host libc)
# must reach the same tcc-boot2 and the same boot2 crt1.o/libc.a/libtcc1.a.
#
# Trusts, beyond seed-forth and the sources: bash, git archive + tar (to
# copy vendor/pnut; the tcc tarball itself is unpacked by bintools), GNU
# patch (for patches/amd64/*.diff), cp/mv/mkdir; sha256sum, cmp, diff, grep,
# wc, date and bc only check and report; unshare (private /tmp, if
# available).
#
# Exit: 0 pass, 1 fail, 77 skip (vendor/pnut or its tcc-0.9.27 tarball
#       missing).
# Env:  BUILDROOT (default ./build-out/pnut-amd64; wiped at start).
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
PNUT=$ROOT/vendor/pnut
PATCHES=$ROOT/patches/amd64
TESTS=$ROOT/tests/pnut/amd64
me=sf-pnut-amd64-check

# --- Pins -----------------------------------------------------------------
PNUT_COMMIT=abc34a5207b1373d0a4e3dcb3d3d6df6e22ae23d
# tcc-0.9.27 source: vendored in pnut at kit/tcc-0.9.27.tar.gz (added by
# pnut commit 920cb3f; upstream release 2017-12-17).
TCC_TGZ_SHA=db0a0bf390c746621b2dc9b8ddf9ff4eeda0c7e3e65e292de5bd8be902eb230d
TCC_VA_LIST_SHA=3204e28b30bc7cbd4ea9520377e69a6feef11e110081bd05d1136fdcbf50c6f1   # tcc-0.9.27/lib/va_list.c
# Chain outputs.
PIN_SF_PNUT64=e05b69f8d5eb010507bd87fde3ef185417da4f1ed73df78a1e8dc26dbc3bfeb8
PIN_PNUT64_G2=5bee065d3332230129036b1e7b154ef2ed8bc2fee643135f227e1c39f856f0de
PIN_PNUT_EXE=b9ebaecc589e9944f25827df112257a2ff1ed0eb9df1c50cb21cd79b21b1d1a1
PIN_BINTOOLS=6aafe3ce91ae38772c607f9b75709046a16bb0df1cd134c6f57ecb6ded156205
PIN_PNUT_EXE_FOR_TCC=b8ade68772e2d360e28109e9ea2d0a91c5091332a269deee0c363e69e77bad53
PIN_TCC_PNUT=97d00391969ea15eb35707d57e14b9f0576bfdfc22d807b6ba568e2fc543b5e4
PIN_TCC_BOOT0=0605483829e454c0a0422c28949ecec94d9b3624d294a9f65d8f16b7923b15de
PIN_TCC_BOOT1=c382b52cc298438c52d6626e9a535b17d1177d0f93e1899bd8d681c58878a886
PIN_TCC_BOOT2=514bc4d3af6b79d2fc99d1178933f3e2ee093ff7ce7362d92dc81708f13fa5c1
PIN_BOOT2_CRT1=9fc015dbe5674217d8d2b92b0bdbed91f3456b2b80afeb72c27a16ffa0247d51
PIN_BOOT2_LIBC=6f35761d40d06c58b1e3a014110b0b59a4dd6db1a140769ddf4474d524d7c86a
PIN_BOOT2_LIBTCC1=21312cd01450bba923f9c1f91193b810693084a5bf98bcc51d2ddce78057307e

if [ ! -f "$PNUT/pnut.c" ]; then
    echo "$me: SKIP: vendor/pnut not checked out (git submodule update --init vendor/pnut)"
    exit 77
fi
if [ ! -f "$PNUT/kit/tcc-0.9.27.tar.gz" ]; then
    echo "$me: SKIP: vendor/pnut/kit/tcc-0.9.27.tar.gz (the tcc-0.9.27 source) not present"
    exit 77
fi

BUILDROOT=${BUILDROOT:-$ROOT/build-out/pnut-amd64}

# Run the whole script with a private /tmp (SF writes /tmp/cc-out;
# test-libc.c writes fixed /tmp paths), as verify.sh does.
if [ -z "${SF_PNUT64_IN_PRIVATE_TMP:-}" ]; then
    mkdir -p "$BUILDROOT"
    BUILDROOT=$(cd "$BUILDROOT" && pwd)
    rm -rf "${BUILDROOT:?}"/*
    mkdir -p "$BUILDROOT/tmp"
    private=1
    case "$ROOT/" in /tmp/*) private=0 ;; esac
    case "$BUILDROOT/" in /tmp/*) private=0 ;; esac
    if [ "$private" = 1 ] && unshare -rm true 2>/dev/null; then
        export SF_PNUT64_IN_PRIVATE_TMP=1 BUILDROOT
        exec unshare -rm bash -c 'mount --bind "$1" /tmp && exec bash "$2"' \
            _ "$BUILDROOT/tmp" "$ROOT/tests/pnut/sf-pnut-amd64-check.sh"
    fi
    echo "$me: no private /tmp (unshare -rm unavailable, or the tree is under /tmp); using the shared /tmp"
fi

REPIN=${SF_PNUT64_REPIN:-0}
fail() { echo "$me: FAIL: $1" >&2; exit 1; }
sha() { sha256sum < "$1" | cut -d' ' -f1; }
T0=$(date +%s.%N)
elapsed() { printf '%.1f' "$(echo "$(date +%s.%N) - $T0" | bc)"; }
# pin LABEL FILE WANT -- the file's sha256 must be WANT.
pin() {
    local got; got=$(sha "$2")
    if [ "$REPIN" = 1 ]; then
        echo "$me: [$(elapsed) s] $1: $got ($(wc -c < "$2") bytes)"
        REPINS+=("$3=$got")
    elif [ "$got" != "${!3}" ]; then
        fail "$1 ($2) is $got, not the pinned ${!3:-<none>} ($3)"
    else
        echo "$me: [$(elapsed) s] $1: ${got:0:16}... ($(wc -c < "$2") bytes) as pinned"
    fi
}
REPINS=()

[ -x seed-forth ] || ./build.sh >/dev/null

# --- Inputs -----------------------------------------------------------------
if git -C "$PNUT" rev-parse HEAD >/dev/null 2>&1; then
    head=$(git -C "$PNUT" rev-parse HEAD)
    [ "$head" = "$PNUT_COMMIT" ] || fail "vendor/pnut is at $head, not the pinned $PNUT_COMMIT"
    mkdir -p "$BUILDROOT/pnut"
    git -C "$PNUT" archive HEAD | tar -x -C "$BUILDROOT/pnut"
else
    fail "vendor/pnut is not a git checkout; cannot confirm it is $PNUT_COMMIT"
fi
got=$(sha "$BUILDROOT/pnut/kit/tcc-0.9.27.tar.gz")
[ "$got" = "$TCC_TGZ_SHA" ] || fail "kit/tcc-0.9.27.tar.gz is $got, not the pinned $TCC_TGZ_SHA — refusing to use it"
echo "$me: inputs: pnut $PNUT_COMMIT, tcc-0.9.27.tar.gz ${TCC_TGZ_SHA:0:16}... as pinned"

# --- Stage 1: SF compiles pnut.c for amd64 ----------------------------------
W=$BUILDROOT
SRC=$W/sf-input.c
{ echo '#define target_x86_64_linux 1'; echo '#define ONE_PASS_GENERATOR 1'; cat "$W/pnut/pnut.c"; } > "$SRC"
rm -f /tmp/cc-out
rc=0
(cd "$W/pnut" && cat "$ROOT/010-lib.fth" "$ROOT"/[0-9][0-9][0-9]-cc-*.fth "$SRC" | "$ROOT/seed-forth") \
    2> "$W/sf.err" || rc=$?
[ "$rc" = 0 ] && [ -f /tmp/cc-out ] || fail "SF could not compile pnut.c: $(tail -n 1 "$W/sf.err") (exit $rc)"
mv /tmp/cc-out "$W/sf-pnut64"; chmod +x "$W/sf-pnut64"
pin "stage 1: SF -> sf-pnut64" "$W/sf-pnut64" PIN_SF_PNUT64

# --- Stage 2: self-hosting fixed point ---------------------------------------
X=(-Dtarget_x86_64_linux -DONE_PASS_GENERATOR)
(cd "$W/pnut" && "$W/sf-pnut64" pnut.c "${X[@]}" -o "$W/pnut64-g2" \
    && "$W/pnut64-g2" pnut.c "${X[@]}" -o "$W/pnut64-g3") > "$W/g2g3.log" 2>&1 \
    || fail "pnut64 self-host (see $W/g2g3.log)"
cmp "$W/pnut64-g2" "$W/pnut64-g3" || fail "pnut64-g2 != pnut64-g3"
pin "stage 2: pnut64-g2 = pnut64-g3" "$W/pnut64-g2" PIN_PNUT64_G2

# --- Stage 3: pnut-exe and bintools ------------------------------------------
K=$W/kit
cp -r "$W/pnut" "$K"
cd "$K"
{
    ./utils/process-includes.sh kit/bintools/bintools-base.c > bintools.c
    cp kit/bintools-libc.c .
    for f in fcntl math pnut_lib setjmp stdio stdlib string unistd stdarg; do cp portable_libc/include/$f.h .; done
    cp portable_libc/include/sys/stat.h portable_libc/include/sys/types.h .
    for f in math pnut_lib setjmp stdio stdlib string; do cp portable_libc/src/$f.c .; done
} 2> "$W/kit-prep.log"
KIT_OPTS=(-Dtarget_x86_64_linux -DONE_PASS_GENERATOR -DUNDEFINED_LABELS_ARE_RUNTIME_ERRORS
          -DENABLE_PNUT_INLINE_INTERRUPT -DNO_BUILTIN_LIBC)
"$W/sf-pnut64" pnut.c "${KIT_OPTS[@]}" -o pnut-exe > "$W/pnut-exe.log" 2>&1 || fail "pnut-exe (see $W/pnut-exe.log)"
pin "stage 3: pnut-exe" pnut-exe PIN_PNUT_EXE
./pnut-exe -D FLAT_INCLUDES -I ./ bintools.c bintools-libc.c -o bintools > "$W/bintools.log" 2>&1 \
    || fail "bintools (see $W/bintools.log)"
pin "stage 3: bintools" bintools PIN_BINTOOLS

# --- Stage 4: tcc-0.9.27 sources and libc64 ------------------------------------
{
    ./bintools ungz --file kit/tcc-0.9.27.tar.gz --output tcc-0.9.27.tar
    ./bintools untar tcc-0.9.27.tar
    ./bintools mkdir -p build
    ./bintools cp kit/config.h tcc-0.9.27/config.h
} > "$W/unpack.log" 2>&1 || fail "unpacking tcc-0.9.27 (see $W/unpack.log)"
got=$(sha tcc-0.9.27/lib/va_list.c)
[ "$got" = "$TCC_VA_LIST_SHA" ] || fail "tcc-0.9.27/lib/va_list.c is $got, not the pinned $TCC_VA_LIST_SHA"
TP=kit/tcc-patches/0.9.27
for p in tccpp.c:array_sizeof tcc.h:attribute tcc.h:bitfields tccgen.c:float_negation \
         tccgen.c:float_zero_division_check tccgen.c:long_double_codegen \
         tccpp.c:scientific-notation-parser libtcc.c:sscanf_TCC_VERSION; do
    ./bintools simple-patch "tcc-0.9.27/${p%%:*}" "$TP/${p#*:}.before" "$TP/${p#*:}.after" \
        >> "$W/patch.log" 2>&1 || fail "kit patch ${p#*:} (see $W/patch.log)"
done
for p in "$PATCHES"/tcc/*.diff; do
    patch -s -p1 -F0 -N -d tcc-0.9.27 < "$p" >> "$W/patch.log" 2>&1 || fail "$(basename "$p") does not apply (see $W/patch.log)"
done
cp -r portable_libc libc64
for p in "$PATCHES"/libc/*.diff; do
    patch -s -p1 -F0 -N -d libc64 < "$p" >> "$W/patch.log" 2>&1 || fail "$(basename "$p") does not apply (see $W/patch.log)"
done
patch -s -F0 -o pnut-for-tcc.c pnut.c < "$PATCHES/pnut/01-heap-size.diff" >> "$W/patch.log" 2>&1 \
    || fail "01-heap-size.diff does not apply (see $W/patch.log)"
echo "$me: [$(elapsed) s] stage 4: tcc-0.9.27 + 8 kit patches + $(ls "$PATCHES"/tcc/*.diff | wc -l) amd64 patches; libc64 = portable_libc + $(ls "$PATCHES"/libc/*.diff | wc -l) patches"

# --- Stage 5: pnut-exe-for-tcc -----------------------------------------------
OPTS2=(-Dtarget_x86_64_linux -DUNDEFINED_LABELS_ARE_RUNTIME_ERRORS -DENABLE_PNUT_INLINE_INTERRUPT
       -DNO_BUILTIN_LIBC -DSAFE_MODE)
./pnut-exe pnut-for-tcc.c "${OPTS2[@]}" -I libc64/include/ libc64/libc.c -o build/pnut-exe-for-tcc \
    > "$W/pnut-exe-for-tcc.log" 2>&1 || fail "pnut-exe-for-tcc (see $W/pnut-exe-for-tcc.log)"
pin "stage 5: pnut-exe-for-tcc" build/pnut-exe-for-tcc PIN_PNUT_EXE_FOR_TCC

# --- Stage 6: tcc-pnut, tcc-boot0..3 -----------------------------------------
# The -D flags kit/bootstrap.sh gives tcc-pnut, for x86_64.
TCC_PNUT_FLAGS=(-D BOOTSTRAP=1 -D HAVE_LONG_LONG=1 -D TCC_TARGET_X86_64=1
    -D 'CONFIG_SYSROOT="/"' -D 'CONFIG_TCC_CRTPREFIX="build/boot0-lib"'
    -D 'CONFIG_TCC_ELFINTERP="/mes/loader"' -D 'CONFIG_TCC_SYSINCLUDEPATHS="libc64/include"'
    -D 'TCC_LIBGCC="build/boot0-lib/libc.a"' -D CONFIG_TCC_LIBTCC1_MES=0 -D CONFIG_TCCBOOT=1
    -D CONFIG_TCC_STATIC=1 -D CONFIG_USE_LIBGCC=1 -D 'TCC_VERSION="0.9.27"' -D ONE_SOURCE=1
    -D 'CONFIG_TCCDIR="build/boot0-lib/tcc"')
build/pnut-exe-for-tcc -D PNUT_CC=1 "${TCC_PNUT_FLAGS[@]}" tcc-0.9.27/tcc.c \
    -I libc64/include/ libc64/libc.c -D __intptr_t_defined=1 -o build/tcc-pnut \
    > "$W/tcc-pnut.log" 2>&1 || fail "tcc-pnut (see $W/tcc-pnut.log)"
./bintools chmod 755 build/tcc-pnut
pin "stage 6: tcc-pnut" build/tcc-pnut PIN_TCC_PNUT

# go CC NEW [LIBNAME] -- kit/bootstrap.sh's go(), for TCC_TARGET_X86_64 and
# libc64, with tcc's lib/va_list.c (x86_64 va_arg support) in libtcc1.a.
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
go build/tcc-pnut boot0 > "$W/boot0.log" 2>&1 || fail "tcc-boot0 (see $W/boot0.log)"
pin "stage 6: tcc-boot0" build/tcc-boot0 PIN_TCC_BOOT0
go build/tcc-boot0 boot1 > "$W/boot1.log" 2>&1 || fail "tcc-boot1 (see $W/boot1.log)"
pin "stage 6: tcc-boot1" build/tcc-boot1 PIN_TCC_BOOT1
go build/tcc-boot1 boot2 > "$W/boot2.log" 2>&1 || fail "tcc-boot2 (see $W/boot2.log)"
go build/tcc-boot2 boot3 boot2 > "$W/boot3.log" 2>&1 || fail "tcc-boot3 (see $W/boot3.log)"
cmp build/tcc-boot2 build/tcc-boot3 || fail "tcc-boot2 != tcc-boot3"
cmp build/tcc-boot2.o build/tcc-boot3.o || fail "tcc-boot2.o != tcc-boot3.o"
pin "stage 6: tcc-boot2 = tcc-boot3" build/tcc-boot2 PIN_TCC_BOOT2
pin "stage 6: boot2-lib/crt1.o" build/boot2-lib/crt1.o PIN_BOOT2_CRT1
pin "stage 6: boot2-lib/libc.a" build/boot2-lib/libc.a PIN_BOOT2_LIBC
pin "stage 6: boot2-lib/tcc/libtcc1.a" build/boot2-lib/tcc/libtcc1.a PIN_BOOT2_LIBTCC1

# --- Stage 7: the result works -------------------------------------------------
# run NAME WANT-EXIT EXPECTED-STDOUT CMD... -- run a test program.
run() {
    local name=$1 want=$2 expect=$3 rc=0; shift 3
    "$@" > "$W/$name.stdout" 2> "$W/$name.stderr" || rc=$?
    [ "$rc" = "$want" ] || fail "$name exited $rc, not $want (see $W/$name.stdout)"
    if [ -n "$expect" ]; then
        cmp -s "$expect" "$W/$name.stdout" || { diff "$expect" "$W/$name.stdout" >&2 || true; fail "$name printed something else"; }
    fi
}
T=$W/tests; mkdir -p "$T"
for t in t64 hello printf; do
    build/tcc-boot2 -static "$TESTS/$t.c" -o "$T/$t" > "$W/cc-$t.log" 2>&1 || fail "tcc-boot2 could not compile $t.c (see $W/cc-$t.log)"
done
run t64 0 "$TESTS/t64.out" "$T/t64"
run hello 7 "$TESTS/hello.out" "$T/hello" a b
run printf 0 "$TESTS/printf.out" "$T/printf"
echo "$me: [$(elapsed) s] stage 7: tcc-boot2 builds t64.c, hello.c, printf.c; each prints what it should"
build/tcc-boot2 -static portable_libc/test-libc.c -o "$T/test-libc" > "$W/cc-test-libc.log" 2>&1 \
    || fail "tcc-boot2 could not compile test-libc.c (see $W/cc-test-libc.log)"
run test-libc 0 "" "$T/test-libc"
grep -q '^All tests passed!$' "$W/test-libc.stdout" || fail "test-libc.c under tcc-boot2 (see $W/test-libc.stdout)"
echo "$me: [$(elapsed) s] stage 7: tcc-boot2 + libc64 pass portable_libc's test-libc.c ($(grep -c '^PASS' "$W/test-libc.stdout") checks)"
./pnut-exe -I libc64/include/ libc64/libc.c "$TESTS/printf.c" -o "$T/printf-pnut" \
    > "$W/cc-printf-pnut.log" 2>&1 || fail "pnut-exe could not compile printf.c (see $W/cc-printf-pnut.log)"
run printf-pnut 0 "$TESTS/printf.out" "$T/printf-pnut"
echo "$me: [$(elapsed) s] stage 7: pnut-exe + libc64 passes printf.c too"
# tcc-boot2 builds pnut (-Dintptr_t=long: portable_libc's stdint.h is empty).
build/tcc-boot2 -static -Dintptr_t=long "${X[@]}" pnut.c -o "$T/pnut-by-tcc" > "$W/cc-pnut.log" 2>&1 \
    || fail "tcc-boot2 could not compile pnut.c (see $W/cc-pnut.log)"
"$T/pnut-by-tcc" pnut.c "${X[@]}" -o "$T/pnut64-g2-by-tcc" > "$W/pnut-by-tcc.log" 2>&1 \
    || fail "tcc-built pnut could not compile pnut.c (see $W/pnut-by-tcc.log)"
cmp "$W/pnut64-g2" "$T/pnut64-g2-by-tcc" || fail "tcc-built pnut does not rebuild pnut64-g2"
echo "$me: [$(elapsed) s] stage 7: a tcc-boot2-built pnut rebuilds pnut64-g2 byte for byte"

# --- Reference comparison against gcc (SF_PNUT64_GCC_ORACLE=1 only) -----------
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

if [ "$REPIN" = 1 ]; then
    echo "$me: REPIN: paste these into the pins above and into REPRODUCIBLE.md:"
    printf '%s\n' "${REPINS[@]}"
    exit 1
fi
if [ "${SF_PNUT64_GCC_ORACLE:-0}" = 1 ]; then
    echo "$me: PASS in $(elapsed) s (tcc-boot2 = tcc-boot3, x86_64; the gcc references agree)"
else
    echo "$me: PASS in $(elapsed) s (tcc-boot2 = tcc-boot3, x86_64, no gcc)"
fi
