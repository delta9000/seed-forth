#!/usr/bin/env bash
# sf-pnut-check.sh — the Forth C compiler builds pnut, unmodified.
#
# Stage 1.  seed-forth's C compiler (010-lib.fth + [0-9][0-9][0-9]-cc-*.fth,
#           "SF") compiles vendor/pnut/pnut.c exactly as shipped (pnut
#           abc34a5): no rewrite, no external preprocessor, no C source
#           added.  SF reads the program from stdin, so it has no -D flag;
#           the script puts the configuration on the stream in front of
#           pnut.c as `#define NAME 1` lines, which is what -D NAME does.
#           The configuration is the one pnut's own `compile-with-M2-Planet`
#           CI job uses (and REPRODUCIBLE.md's M2-Planet route):
#               -D target_i386_linux -D NO_TERNARY_SUPPORT
#               -D ONE_PASS_GENERATOR -D SMALL_HEAP
#           pnut.c's own #include "x86.c" (-> exe.c, elf.c) is resolved
#           relative to vendor/pnut, where the compiler runs.  The result,
#           sf-pnut, is an amd64 ELF: a pnut that generates i386 code.
#           On a compile failure the script prints the compiler's
#           "cc: line N: error C" (Appendix G) and the preprocessed source
#           around line N, and exits 1.
# Stage 2.  sf-pnut compiles pnut.c for pnut's TCC kit, with the kit's
#           options (PNUT_EXE_TCC_OPTIONS in kit/bootstrap.sh), and the
#           result must be byte-identical to what an M2-Planet-built pnut
#           (built by bootstrap.sh's cc-out-v3, M1 and hex2 with the same
#           CI configuration) makes of the same command.  No gcc anywhere.
# Stage 3.  (SF_PNUT_TCC=1 only; slow, ~90 s) the kit's own bootstrap.sh
#           continues from that pnut-exe to tcc-0.9.27; tcc-boot2 and
#           tcc-boot3 must both be pnut's published 03e96a1a... .
#
# Exit: 0 pass, 1 fail, 77 skip (vendor/pnut not checked out).
# Env:  BUILDROOT (default ./build-out/pnut), BOOTSTRAP_OUT (default
#       ./build-out/out; ./bootstrap.sh is run if its cc-out-v3 is missing).
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
PNUT=$ROOT/vendor/pnut
if [ ! -f "$PNUT/pnut.c" ]; then
    echo "sf-pnut-check: SKIP: vendor/pnut not checked out (git submodule update --init vendor/pnut)"
    exit 77
fi
BUILDROOT=${BUILDROOT:-$ROOT/build-out/pnut}
BOOTSTRAP_OUT=${BOOTSTRAP_OUT:-$ROOT/build-out/out}
case $BOOTSTRAP_OUT in /*) ;; *) BOOTSTRAP_OUT=$ROOT/$BOOTSTRAP_OUT ;; esac
mkdir -p "$BUILDROOT"
BUILDROOT=$(cd "$BUILDROOT" && pwd)
fail() { echo "sf-pnut-check: FAIL: $1" >&2; exit 1; }

[ -x seed-forth ] || ./build.sh >/dev/null

CONFIG=(target_i386_linux NO_TERNARY_SUPPORT ONE_PASS_GENERATOR SMALL_HEAP)
KIT_OPTS=(-Dtarget_i386_linux -DONE_PASS_GENERATOR -DSUPPORT_EMULATED_INT64
          -DUNDEFINED_LABELS_ARE_RUNTIME_ERRORS -DENABLE_PNUT_INLINE_INTERRUPT
          -DNO_BUILTIN_LIBC)

# The C program SF reads: the -D lines, then pnut.c as shipped.
SRC=$BUILDROOT/sf-input.c
{ for d in "${CONFIG[@]}"; do echo "#define $d 1"; done; cat "$PNUT/pnut.c"; } > "$SRC"

# run_sf FORTH-TAIL -- feed the compiler vocabulary (less 120-cc-main.fth
# when a different driver is given) plus SRC to seed-forth in vendor/pnut,
# with a private /tmp when unshare allows it, so /tmp/cc-out is not shared.
PTMP=$BUILDROOT/tmp
run_sf() {
    rm -rf "$PTMP"; mkdir -p "$PTMP"
    local rc=0
    if unshare -rm true 2>/dev/null; then
        (cd "$PNUT" && cat "$@" "$SRC" \
            | unshare -rm sh -c 'mount --bind "$1" /tmp && exec /proc/self/fd/3 3<&3' \
                _ "$PTMP" 3< "$ROOT/seed-forth") || rc=$?
        OUTDIR=$PTMP
    else
        (cd "$PNUT" && cat "$@" "$SRC" | "$ROOT/seed-forth") || rc=$?
        OUTDIR=/tmp
    fi
    return $rc
}
LIB=$ROOT/010-lib.fth
CC=()
while IFS= read -r source; do CC+=("$source"); done < <("$ROOT/tools/compiler-layers.sh" "$ROOT")

# --- Stage 1: SF compiles pnut.c -------------------------------------------
rc=0
t0=$(date +%s.%N)
run_sf "$LIB" "${CC[@]}" 2> "$BUILDROOT/sf.err" || rc=$?
t1=$(date +%s.%N)
if [ "$rc" != 0 ] || [ ! -f "$OUTDIR/cc-out" ]; then
    msg=$(tail -n 1 "$BUILDROOT/sf.err")
    echo "sf-pnut-check: SF could not compile pnut.c: $msg (exit $rc)"
    line=$(echo "$msg" | sed -n 's/^cc: line \([0-9]*\): error [0-9]*$/\1/p')
    if [ -n "$line" ]; then
        # The line is in the preprocessed source (includes spliced in).
        # Re-run the preprocessor alone and dump cc-src-buf to show it.
        DUMP=$BUILDROOT/dump.fth
        cat > "$DUMP" <<'EOF'
create cc-dump-path  s, /tmp/sf-pp.c  [lit] 0 c,
: cc-dump
  cc-load-stdin cc-preprocess
  cc-dump-path [lit] 577 [lit] 420 open
  dup cc-src-buf cc-src-len @ write drop close drop bye ;
cc-dump
EOF
        NOMAIN=()
        for f in "${CC[@]}"; do case $f in *120-cc-main.fth) ;; *) NOMAIN+=("$f") ;; esac; done
        run_sf "$LIB" "${NOMAIN[@]}" "$DUMP" 2>/dev/null || true
        if [ -f "$OUTDIR/sf-pp.c" ]; then
            cp "$OUTDIR/sf-pp.c" "$BUILDROOT/sf-pp.c"
            echo "sf-pnut-check: preprocessed source lines $((line > 3 ? line - 3 : 1))-$line ($BUILDROOT/sf-pp.c):"
            sed -n "$((line > 3 ? line - 3 : 1)),${line}p" "$BUILDROOT/sf-pp.c" | sed 's/^/    | /'
        fi
    fi
    exit 1
fi
mv "$OUTDIR/cc-out" "$BUILDROOT/sf-pnut"
chmod +x "$BUILDROOT/sf-pnut"
printf 'sf-pnut-check: stage 1: SF compiled pnut.c -> sf-pnut (%s bytes, %.1f s)\n' \
    "$(wc -c < "$BUILDROOT/sf-pnut")" "$(echo "$t1 - $t0" | bc)"

# --- Stage 2: sf-pnut's pnut-exe == M2-Planet-built pnut's ------------------
if [ ! -x "$BOOTSTRAP_OUT/cc-out-v3" ]; then
    ./bootstrap.sh > "$BUILDROOT/bootstrap.log" 2>&1 || fail "bootstrap.sh (see $BUILDROOT/bootstrap.log)"
fi
L=$ROOT/vendor/M2-Planet/M2libc
(cd "$PNUT" && "$BOOTSTRAP_OUT/cc-out-v3" --architecture x86 \
    $(for d in "${CONFIG[@]}"; do printf -- '-D %s ' "$d"; done) \
    -I "$L" --expand-includes pnut.c -o "$BUILDROOT/m2-pnut.M1") > "$BUILDROOT/m2.log" 2>&1 \
    || fail "M2-Planet could not compile pnut.c (see $BUILDROOT/m2.log)"
"$BOOTSTRAP_OUT/M1" -f "$L/x86/x86_defs.M1" -f "$L/x86/libc-full.M1" -f "$BUILDROOT/m2-pnut.M1" \
    --architecture x86 --little-endian -o "$BUILDROOT/m2-pnut.hex2" || fail "M1"
"$BOOTSTRAP_OUT/hex2" --architecture x86 --little-endian --file "$L/x86/ELF-x86.hex2" \
    --file "$BUILDROOT/m2-pnut.hex2" --base-address 0x8048000 --output "$BUILDROOT/m2-pnut" || fail "hex2"
chmod +x "$BUILDROOT/m2-pnut"

(cd "$PNUT" && "$BUILDROOT/sf-pnut" pnut.c "${KIT_OPTS[@]}" -o "$BUILDROOT/pnut-exe-sf") \
    > "$BUILDROOT/sf-pnut.log" 2>&1 || fail "sf-pnut could not compile pnut.c (see $BUILDROOT/sf-pnut.log)"
# m2-pnut is an i386 program.  Without the kernel's IA-32 emulation it
# cannot run; then the comparison is against the pnut-exe it was recorded
# to build (sha256 below; REPRODUCIBLE.md), and stage 3 is skipped.
PNUT_EXE_SHA=19d96d9ed04eacaab4bba58cc3a8fcf180ac4ec88369599ef3c20d349d0fb159
IA32=1
rc=0
(cd "$PNUT" && "$BUILDROOT/m2-pnut" pnut.c "${KIT_OPTS[@]}" -o "$BUILDROOT/pnut-exe-m2") \
    > "$BUILDROOT/m2-pnut.log" 2>&1 || rc=$?
if [ "$rc" = 126 ]; then
    IA32=0
    got=$(sha256sum < "$BUILDROOT/pnut-exe-sf" | cut -d' ' -f1)
    [ "$got" = "$PNUT_EXE_SHA" ] || fail "pnut-exe built by sf-pnut is $got, not the recorded $PNUT_EXE_SHA"
    echo "sf-pnut-check: stage 2: no IA-32 emulation to run m2-pnut; sf-pnut's pnut-exe matches the recorded ${PNUT_EXE_SHA:0:16}..."
else
    [ "$rc" = 0 ] || fail "m2-pnut could not compile pnut.c (i386 binary; see $BUILDROOT/m2-pnut.log)"
    cmp "$BUILDROOT/pnut-exe-sf" "$BUILDROOT/pnut-exe-m2" \
        || fail "pnut-exe built by sf-pnut differs from pnut-exe built by m2-pnut"
    echo "sf-pnut-check: stage 2: sf-pnut and m2-pnut build the same pnut-exe ($(sha256sum < "$BUILDROOT/pnut-exe-sf" | cut -c1-16)...)"
fi

# --- Stage 3 (optional): the kit continues to tcc-0.9.27 --------------------
if [ "${SF_PNUT_TCC:-0}" = 1 ] && [ "$IA32" = 0 ]; then
    echo "sf-pnut-check: stage 3: SKIP (the kit's tools are i386 programs; no IA-32 emulation)"
elif [ "${SF_PNUT_TCC:-0}" = 1 ]; then
    W=$BUILDROOT/kit
    rm -rf "$W"; mkdir -p "$W"
    (cd "$PNUT" && git archive HEAD | tar -x -C "$W")
    (
        cd "$W"
        ./utils/process-includes.sh kit/bintools/bintools-base.c > bintools.c
        cp kit/bintools-libc.c .
        for f in fcntl math pnut_lib setjmp stdio stdlib string unistd stdarg; do cp portable_libc/include/$f.h .; done
        cp portable_libc/include/sys/stat.h portable_libc/include/sys/types.h .
        for f in math pnut_lib setjmp stdio stdlib string; do cp portable_libc/src/$f.c .; done
        cp -r kit/tcc-patches/0.9.27 tcc-patches
        printf '#!/bin/sh\nexit 0\n' > jammed-no-exec.sh; chmod +x jammed-no-exec.sh
        cp "$BUILDROOT/pnut-exe-sf" pnut-exe
        BOOTSTRAP_SHELL=sh sh kit/bootstrap.sh
    ) > "$BUILDROOT/kit.log" 2>&1 || fail "kit/bootstrap.sh (see $BUILDROOT/kit.log)"
    want=03e96a1a63cc9bb3f577a14e50d20476507e3759bdc803f79e31d184bba44185
    for b in tcc-boot2 tcc-boot3; do
        got=$(sha256sum < "$W/build/$b" | cut -d' ' -f1)
        [ "$got" = "$want" ] || fail "$b is $got, not pnut's published $want"
    done
    echo "sf-pnut-check: stage 3: tcc-boot2 = tcc-boot3 = ${want:0:16}... (pnut kit README)"
fi
echo "sf-pnut-check: PASS"
