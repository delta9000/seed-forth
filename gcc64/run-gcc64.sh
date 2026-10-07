#!/usr/bin/env bash
# gcc64/run-gcc64.sh -- seed-forth's pure-amd64 chain, continued past
# tcc-0.9.27 to GCC 15.2.0 by way of musl (see gcc64/README.md):
#
#   stage 0   seed-forth -> ... -> tcc-boot2 (portable_libc):
#                        tests/tcc/kernel-route-check.sh (raw source inputs)
#   stage 1   tcc-p0   : tcc-boot2 builds tcc (+live-bootstrap tcc patches) against a
#                        "bridge" copy of libc64 (real ldexp/strtod, 1 GiB heap)
#   stage 2   musl-1   : tcc-p0 builds musl-1.1.24 (x86_64, patched for tcc)
#             tcc-1    : tcc-p0 builds tcc against musl-1
#             musl-k / tcc-k, k=2,3 : each tcc rebuilds musl then itself, into the
#                        final prefix tc/; fixed point musl-2 = musl-3, tcc-2 = tcc-3
#   stage 3   tests2   : tcc's own tests/tests2 under tcc-boot2 and the musl tcc
#   stage 4   binutils-2.30 by tcc
#   stage 5   flex-2.6.4 and gcc-4.0.4 ("gcc-A") by tcc
#   bridge    instead of stages 0-5 (GCC64_DIRECT): the direct route's GCC 4.0.4, built
#             from the Forth compiler without TinyCC, builds binutils-2.30 and gcc-A in
#             the layout stage 6 expects (see bridge() and gcc64/README.md)
#   stage 6   gcc-A builds gcc-B, gcc-B builds gcc-C; B = C
#   stage 7   gcc-B rebuilds musl (the sysroot), gmp, mpfr, mpc (+ make check)
#   stage 8   gcc-4.7.4 (C, C++) by gcc-B
#   stage 9   binutils-2.41 by gcc-4.7.4
#   stage 10  gcc-10.5.0 (C, C++) by gcc-4.7.4
#   stage 11  gcc-15.2.0 (C, C++), full 3-stage bootstrap seeded by gcc-10.5.0
#             (make compare: stage2 = stage3)
#   stage 12  verify   : every gcc compiles and runs hello/64-bit/float/C++; the final
#                        gcc's -v, sysroot, as and ld all point into the chain
#   then      pins     : every artifact in gcc64/HASHES is compared (see below)
#
# Layout: this script and its helpers (build-gcc*.sh, mktcc.sh, simple-patch.py)
# live in gcc64/; patches in patches/gcc64/; test programs in tests/gcc64/;
# sources are listed with their sha256 in gcc64/SOURCES and fetched into a cache.
# Everything built goes into BUILDROOT; nothing is written into the tree outside it.
#
# Host tools (build glue only; never a compiler/assembler/linker): the HOSTTOOLS list
# below, symlinked into $W/hostbin.  PATH is exactly $W/guard:$W/hostbin (plus a
# stage's own chain-built bin dirs), so /usr/bin is not searched at all.  $W/guard
# shadows gcc/cc/ld/as/ar/... with scripts that fail loudly and log to
# $W/guard/hits.log (cwd in where.log).  Absolute host paths still reachable: /bin/sh
# (#! lines, system()), /usr/bin/env, and the host m4, which flex execs at run time
# (via hostbin/m4).
#
# As root (real, or mapped root in a user namespace such as verify.sh's), the script
# re-execs itself in a private mount namespace in which /dev/null is bind-mounted
# onto itself, so no tool can unlink or replace the host's /dev/null (unlink gets
# EBUSY), and a refusing script is bind-mounted over every host compiler, assembler
# and linker reachable by absolute path (/lib/cpp, /usr/bin/gcc*, ...).
# GCC64_TRACE=FILE additionally runs everything under strace -f (execve and unlink
# only) to list every program executed.
#
# Usage: gcc64/run-gcc64.sh [stage ...]           all stages, or the ones named, in
#                                                 BUILDROOT (each stage wipes and
#                                                 rebuilds only its own outputs, so a
#                                                 later stage can be re-run in place)
#        gcc64/run-gcc64.sh --new DIR [stage ...] the same, in DIR, which must not exist
#        gcc64/run-gcc64.sh --fetch               fill the source cache and exit
#
# Env:   BUILDROOT     build directory (default build-out/gcc64; created if missing,
#                      never wiped as a whole).  Absolute paths under it are baked
#                      into the binaries, so artifact hashes depend on it; see HASHES.
#        GCC64_CACHE   source cache (default build-out/gcc64-cache).  Every file is
#                      checked against gcc64/SOURCES before use; with all of them
#                      cached, no network is needed.
#        GCC64_STAGE0  a finished direct TinyCC or named pnut-control work root (e.g.
#                      build-out/pnut-amd64): stage 0 checks its tcc-boot2 and boot2
#                      libraries against tools/tcc.recipe and copies its kit
#                      instead of re-running the direct route. Reuse verifies
#                      artifacts, not the supplied root's compiler provenance.
#        GCC64_DIRECT, GCC64_OYACC, GCC64_FLEX  for the bridge stage: a finished
#                      gcc-direct/stage-d.py WORK and the Forth-built oyacc and flex
#                      2.5.11.  With GCC64_DIRECT set, the default stages are
#                      bridge stage6 ... stage12.
#        GCC64_REPIN=1 print the pins step's hashes instead of failing on them.
#        JOBS          make -j (default 4).
#
# Exit:  0 pass, 1 fail, 77 skip (a source is neither cached nor fetchable, or
#        required vendored TinyCC/libc sources are missing for stage 0).
set -euo pipefail
GCC64=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$GCC64/.." && pwd)
me=run-gcc64
SELF=$GCC64/run-gcc64.sh

if [ "${1:-}" = --new ]; then
    [ -n "${2:-}" ] || { echo "$me: --new needs a directory" >&2; exit 1; }
    [ ! -e "$2" ] || { echo "$me: $2 exists; --new wants a fresh directory" >&2; exit 1; }
    mkdir -p "$2"; BUILDROOT=$2; shift 2
fi
BUILDROOT=${BUILDROOT:-$ROOT/build-out/gcc64}
mkdir -p "$BUILDROOT"
W=$(cd "$BUILDROOT" && pwd)
GCC64_CACHE=${GCC64_CACHE:-$ROOT/build-out/gcc64-cache}
mkdir -p "$GCC64_CACHE"
GCC64_CACHE=$(cd "$GCC64_CACHE" && pwd)
export BUILDROOT=$W GCC64_CACHE

if [ "$(id -u)" = 0 ] && [ -z "${GCC64_NS:-}" ] && [ "${1:-}" != --fetch ] && command -v unshare > /dev/null; then
    export GCC64_NS=1 GCC64_W=$W
    # _abs: bind-mounted (inside the namespace only) over every host compiler, assembler
    # and linker reachable by absolute path, e.g. autoconf's /lib/cpp fallback and
    # /usr/libexec/gcc/*/cc1plus behind it; the gcc/llvm libexec trees get an empty tmpfs.
    mkdir -p "$W/guard"
    printf '#!/bin/sh\necho "GUARD: host $0 invoked: $*" >&2\necho "GUARD $0 $*" >> %s/guard/hits.log\necho "GUARD $0 $* [cwd $PWD]" >> %s/guard/where.log\nexit 99\n' \
        "$W" "$W" > "$W/guard/_abs"
    chmod +x "$W/guard/_abs"
    exec unshare -m --propagation private /bin/sh -c '
        mount --bind /dev/null /dev/null || exit 1
        for f in /lib/cpp /usr/bin/cpp* /usr/bin/gcc* /usr/bin/g++* /usr/bin/cc /usr/bin/c++ /usr/bin/c89* \
                 /usr/bin/c99* /usr/bin/x86_64-linux-gnu-* /usr/bin/as /usr/bin/ld /usr/bin/ld.bfd /usr/bin/ld.gold /usr/bin/ld.lld* /usr/bin/ld64* \
                 /usr/bin/clang* /usr/bin/lto-dump* /usr/bin/tcc /usr/local/bin/gcc /usr/local/bin/cc; do
            [ -e "$f" ] || continue
            mount --bind "$GCC64_W/guard/_abs" "$f" || exit 1
        done
        for d in /usr/libexec/gcc /usr/lib/gcc /usr/lib/llvm-*; do
            [ -d "$d" ] && { mount -t tmpfs -o ro,size=64k none "$d" || exit 1; }
        done
        if [ -n "${GCC64_TRACE:-}" ]; then
            exec strace -f --seccomp-bpf -qq -e trace=execve,unlink,unlinkat -e signal=none \
                 -s 200 -o "$GCC64_TRACE" "$@"
        fi
        exec "$@"' sh "$SELF" "$@"
fi
unset GCC64_W
D=$GCC64_CACHE
PATCHES=$ROOT/patches/gcc64
TESTS=$ROOT/tests/gcc64
LOG=$W/logs; mkdir -p "$LOG"
JOBS=${JOBS:-4}
export GCC64_W=$W GCC64_PATCHES=$PATCHES JOBS
HOSTPATH=$PATH
# every host program the build may find on PATH (none is a compiler, assembler or linker)
HOSTTOOLS="bash sh make sed grep egrep fgrep awk mawk tr cut sort uniq comm join paste cat tac head tail
  wc cp mv rm rmdir mkdir ln ls touch chmod install readlink realpath basename dirname pwd
  tar gzip gunzip zcat xz unxz bzip2 patch diff cmp sha256sum md5sum cksum find xargs expr env
  uname date sleep test [ true false printf echo tee mktemp od dd du stat id hostname nproc
  getconf timeout nice seq split tsort fold nl sync which bison m4 python3
  git bc unshare mount"   # source fetching and namespace isolation
mkhostbin() {
    local t p; rm -rf "$W/hostbin"; mkdir -p "$W/hostbin"
    for t in $HOSTTOOLS; do
        p=$(PATH=$HOSTPATH type -P "$t") || { echo "$me: host tool $t not found (skipped)" >&2; continue; }
        case $p in /*) ln -s "$p" "$W/hostbin/$t" ;; esac
    done
}
export LC_ALL=C
T0=$(date +%s)
say() { echo "[$me +$(( $(date +%s) - T0 ))s] $*"; }
sha() { sha256sum "$1" | cut -c1-64; }
fail() { echo "$me: FAIL: $*" >&2; exit 1; }
skip() { echo "$me: SKIP: $*"; exit 77; }
# timing: t_start NAME / t_end NAME
declare -A TS
t_start() { TS[$1]=$(date +%s); }
t_end() { local n=$(( $(date +%s) - ${TS[$1]} )); say "$1 done in ${n}s"; echo "$1 ${n}s" >> "$LOG/timings.txt"; }

# --- guard: no host compiler, assembler or linker may run -------------------
mkguard() {
    mkdir -p "$W/guard"
    for t in gcc cc c89 c99 ld as ar ranlib cpp g++ c++ gcc-ar gcc-nm gcc-ranlib nm strip objcopy \
             objdump readelf size strings addr2line c++filt gprof ld.bfd ld.gold gold \
             tcc clang x86_64-linux-gnu-gcc x86_64-linux-gnu-ld x86_64-linux-gnu-as; do
        printf '#!/bin/sh\necho "GUARD: host %s invoked: $*" >&2\necho "GUARD %s $*" >> %s/guard/hits.log\necho "GUARD %s $* [cwd $PWD]" >> %s/guard/where.log\nexit 99\n' \
            "$t" "$t" "$W" "$t" "$W" > "$W/guard/$t"
        chmod +x "$W/guard/$t"
    done
    rm -f "$W/guard/hits.log" "$W/guard/where.log"
}
# configure scripts probe for gcc/cc/ld/nm... by name; those probes hit the guard and
# fail, which is fine.  What must never happen is a guard hit outside configure.
checkguard_probes() {
    [ -s "$W/guard/hits.log" ] || return 0
    say "guard: $(wc -l < "$W/guard/hits.log") configure-time probes of host tools (all refused): $(cut -d' ' -f2 "$W/guard/hits.log" | sort | uniq -c | tr '\n' ' ')"
    grep -v -E ' (conftest|-v$|-V$|--version|-qversion|-B |-p conftest|--help|/dev/null)' "$W/guard/hits.log" \
        && fail "a host tool was invoked outside a configure probe" || true
    cat "$W/guard/where.log" >> "$LOG/guard-probes.log"; rm -f "$W/guard/hits.log" "$W/guard/where.log"
}

# --- sources: gcc64/SOURCES, fetched into $GCC64_CACHE, sha256-checked before use ----
declare -A SRC_SHA SRC_URLS
while read -r name hash urls; do
    case $name in ''|'#'*) continue ;; esac
    SRC_SHA[$name]=$hash; SRC_URLS[$name]=$urls
done < "$GCC64/SOURCES"
# fetch_one NAME URL: put NAME into the cache from URL (see SOURCES for the forms)
fetch_one() {
    local f=$1 u=$2 tmp=$D/.fetch.$$ repo ref commit prefix
    rm -rf "$tmp"; mkdir -p "$tmp"
    case $u in
        git+*)
            u=${u#git+}; prefix=${u##*:}; u=${u%:*}; commit=${u##*@}; u=${u%@*}; ref=${u##*#}; repo=${u%#*}
            PATH=$HOSTPATH git -c advice.detachedHead=false clone -q --depth 1 --branch "$ref" "$repo" "$tmp/git" || return 1
            [ "$(PATH=$HOSTPATH git -C "$tmp/git" rev-parse HEAD)" = "$commit" ] \
                || { echo "$me: $repo $ref is not $commit" >&2; return 1; }
            PATH=$HOSTPATH git -C "$tmp/git" archive --format=tar --prefix="$prefix/" HEAD > "$tmp/out" || return 1 ;;
        *!*)
            PATH=$HOSTPATH curl -fsSL --connect-timeout 20 --max-time 3600 -o "$tmp/outer" "${u%%!*}" || return 1
            tar -xf "$tmp/outer" -O "${u#*!}" > "$tmp/out" || return 1 ;;
        *)
            PATH=$HOSTPATH curl -fsSL --connect-timeout 20 --max-time 3600 -o "$tmp/out" "$u" || return 1 ;;
    esac
    mv "$tmp/out" "$D/$f"; rm -rf "$tmp"
}
# need NAME: make sure the cache holds NAME with the pinned sha256; else fetch it
need() {
    local f=$1 u got
    [ -n "${SRC_SHA[$f]:-}" ] || fail "$f is not listed in gcc64/SOURCES"
    if [ -f "$D/$f" ]; then
        got=$(sha "$D/$f")
        [ "$got" = "${SRC_SHA[$f]}" ] || fail "$D/$f has sha256 $got, not the pinned ${SRC_SHA[$f]}; delete it to refetch"
        return 0
    fi
    for u in ${SRC_URLS[$f]}; do
        say "fetching $f from $u"
        if fetch_one "$f" "$u"; then
            got=$(sha "$D/$f")
            [ "$got" = "${SRC_SHA[$f]}" ] && return 0
            echo "$me: $u gave sha256 $got, not the pinned ${SRC_SHA[$f]}; discarded" >&2
            rm -f "$D/$f"
        fi
        rm -rf "$D/.fetch.$$"
    done
    skip "$f is not in $D and none of its URLs gave the pinned bytes"
}
if [ "${1:-}" = --fetch ]; then
    for f in "${!SRC_SHA[@]}"; do need "$f"; done
    say "all $(echo "${!SRC_SHA[@]}" | wc -w) sources in $D, sha256 as pinned"; exit 0
fi

# --- stage 0: seed-forth -> direct TinyCC -> pinned tcc-boot2 --------------------
K=$W/tccboot/kit
TCC0=$ROOT/tests/tcc/kernel-route-check.sh
TCC0_PINS=$ROOT/tools/tcc.recipe
stage0_copy() {
    local s0=$1 f v
    for f in build/tcc-boot2 build/boot2-lib/crt1.o build/boot2-lib/libc.a \
             build/boot2-lib/tcc/libtcc1.a; do
        v=$(awk -v f="$f" '$1 == "artifact" && $2 == f { print $3 }' "$TCC0_PINS")
        [[ $v =~ ^[0-9a-f]{64}$ ]] || fail "no unique artifact pin for $f in $TCC0_PINS"
        [ -f "$s0/kit/$f" ] || fail "stage 0: $s0/kit/$f missing (run $TCC0 first)"
        [ "$(sha "$s0/kit/$f")" = "$v" ] || fail "stage 0: kit/$f differs from $TCC0_PINS"
    done
    # GCC64_STAGE0 may already name this build's tccboot; do not erase it.
    [ "$s0/kit" = "$K" ] || {
        rm -rf "$W/tccboot"; mkdir -p "$W/tccboot"; cp -a "$s0/kit" "$K"
    }
}
stage0() {
    t_start stage0
    if [ -n "${GCC64_STAGE0:-}" ]; then
        local s0
        s0=$(cd "$GCC64_STAGE0" && pwd) || fail "GCC64_STAGE0=$GCC64_STAGE0 does not exist"
        stage0_copy "$s0"
        echo "$me: stage 0 reused from $s0: artifacts as pinned by $TCC0_PINS (supplied provenance)" > "$LOG/stage0.log"
    else
        local rc=0
        (cd "$ROOT" && ./build.sh && "$TCC0") > "$LOG/stage0.log" 2>&1 || rc=$?
        [ "$rc" = 77 ] && skip "stage 0: $(grep -m1 SKIP "$LOG/stage0.log")"
        [ "$rc" = 0 ] || fail "direct TinyCC route (see $LOG/stage0.log)"
        stage0_copy "$ROOT/build-out/pnut-amd64"
    fi
    tail -1 "$LOG/stage0.log"
    say "tcc-boot2: $(sha "$K/build/tcc-boot2")"
    t_end stage0
}

# --- tcc source tree for this chain -------------------------------------------------
# kit's tcc-0.9.27 (pnut kit patches + patches/amd64/tcc) + live-bootstrap's tcc
# patches + our patches/gcc64/tcc/1*.diff
tcc_src() {
    local s=$W/src/tcc
    rm -rf "$s"; mkdir -p "$W/src"; cp -r "$K/tcc-0.9.27" "$s"
    for p in "$PATCHES"/tcc/*; do patch -s -p1 -F0 -d "$s" < "$p" || fail "tcc patch $p"; done
    for sp in tcctools.c:remove-fileopen tcctools.c:addback-fileopen tccelf.c:check-reloc-null; do
        python3 "$GCC64/simple-patch.py" "$s/${sp%%:*}" "$PATCHES/tcc-simple/${sp#*:}.before" \
            "$PATCHES/tcc-simple/${sp#*:}.after" || fail "simple-patch $sp"
    done
}

# --- stage 1: tcc-p0 (portable_libc + bridge) ---------------------------------------
stage1() {
    t_start stage1
    tcc_src
    local P=$W/p0 B=$W/src/libc64-bridge
    rm -rf "$P" "$B"; mkdir -p "$P/bin" "$P/lib/tcc"
    cp -r "$K/libc64" "$B"
    patch -s -p1 -F0 -d "$B" < "$PATCHES/libc64/01-bridge.diff" || fail "bridge patch"
    cp -r "$B/include" "$P/include"
    cp "$K"/build/boot2-lib/{crt1.o,crti.o,crtn.o} "$P/lib/"
    cp "$K/build/boot2-lib/tcc/libtcc1.a" "$P/lib/tcc/"
    (
        cd "$K"
        build/tcc-boot2 -c -D ADD_LIBC_STUB -I "$B/include" -o "$P/lib/libc.o" "$B/libc.c"
        build/tcc-boot2 -ar cr "$P/lib/libc.a" "$P/lib/libc.o"; rm "$P/lib/libc.o"
        build/tcc-boot2 -static -o "$P/bin/tcc" -D BOOTSTRAP=1 -D __SIZEOF_LONG_LONG__=8 -D HAVE_FLOAT=1 \
            -D HAVE_BITFIELD=1 -D HAVE_LONG_LONG=1 -D HAVE_SETJMP=1 -I libc64/include -D TCC_TARGET_X86_64=1 \
            -D "CONFIG_TCCDIR=\"$P/lib/tcc\"" -D "CONFIG_TCC_CRTPREFIX=\"$P/lib\"" \
            -D "CONFIG_TCC_LIBPATHS=\"$P/lib:$P/lib/tcc\"" -D "CONFIG_TCC_SYSINCLUDEPATHS=\"$P/include\"" \
            -D "TCC_LIBGCC=\"$P/lib/libc.a\"" -D 'TCC_LIBTCC1="libtcc1.a"' -D 'CONFIG_TCC_ELFINTERP="/mes/loader"' \
            -D CONFIG_TCCBOOT=1 -D CONFIG_TCC_STATIC=1 -D CONFIG_USE_LIBGCC=1 -D 'TCC_VERSION="0.9.27"' \
            -D ONE_SOURCE=1 -L "$P/lib" "$W/src/tcc/tcc.c"
    ) > "$LOG/stage1.log" 2>&1 || fail "tcc-p0 (see $LOG/stage1.log)"
    say "tcc-p0: $(sha "$P/bin/tcc")"
    checkguard_probes; t_end stage1
}

# --- stage 2: musl <-> tcc to a fixed point ---------------------------------------------
musl_src() {  # musl_src DIR
    local s=$1
    need musl-1.1.24.tar.gz
    rm -rf "$s" "$s.tmp"; mkdir -p "$s.tmp"
    tar -xzf "$D/musl-1.1.24.tar.gz" -C "$s.tmp"; mv "$s.tmp/musl-1.1.24" "$s"; rmdir "$s.tmp"
    for p in "$PATCHES"/musl-1.1.24/*; do patch -s -p1 -F0 -d "$s" < "$p" || fail "musl patch $p"; done
    rm -rf "$s/src/complex"                                   # tcc has no _Complex (as live-bootstrap)
    rm "$s"/src/math/x86_64/{fabs,fabsf,lrintf,sqrtf,llrint,lrint,llrintf,sqrt}.s  # SSE insns tcc cannot assemble; C versions used
}
build_musl() {  # build_musl CC PREFIX NAME
    local cc=$1 pre=$2 name=$3 s=$W/src/musl-$3
    musl_src "$s"
    (
        cd "$s"
        CC=$cc ./configure --target=x86_64 --host=x86_64 --disable-shared --prefix="$pre"
        make -j"$JOBS" CROSS_COMPILE= AR="$cc -ar" RANLIB=true
        make install CROSS_COMPILE= AR="$cc -ar" RANLIB=true
    ) > "$LOG/$name.log" 2>&1 || fail "$name (see $LOG/$name.log)"
    rm -rf "$s"
}
stage2() {
    t_start stage2
    local TC=$W/tc
    rm -rf "$W/m1" "$W/t1" "$TC" "$W/save"; mkdir -p "$W/save"
    build_musl "$W/p0/bin/tcc" "$W/m1" musl-1
    say "musl-1 libc.a: $(sha "$W/m1/lib/libc.a")"
    mkdir -p "$W/t1"; cp -r "$W/m1/include" "$W/m1/lib" "$W/t1/"
    "$GCC64/mktcc.sh" "$W/p0/bin/tcc" "$W/m1" "$W/t1" "$W/src/tcc" > "$LOG/tcc-1.log" 2>&1 || fail "tcc-1"
    say "tcc-1: $(sha "$W/t1/bin/tcc")"
    local cc=$W/t1/bin/tcc k
    for k in 2 3 4; do
        rm -rf "$TC"; mkdir -p "$TC"
        build_musl "$cc" "$TC" "musl-$k"
        cp "$TC/lib/libc.a" "$W/save/libc-$k.a"
        "$GCC64/mktcc.sh" "$cc" "$TC" "$TC" "$W/src/tcc" > "$LOG/tcc-$k.log" 2>&1 || fail "tcc-$k"
        cp "$TC/bin/tcc" "$W/save/tcc-$k"; cp "$TC/lib/tcc/libtcc1.a" "$W/save/libtcc1-$k.a"
        say "musl-$k libc.a: $(sha "$W/save/libc-$k.a")  tcc-$k: $(sha "$W/save/tcc-$k")"
        cc=$W/save/tcc-$k
        if [ "$k" -ge 3 ] && cmp -s "$W/save/libc-$k.a" "$W/save/libc-$((k-1)).a" \
           && cmp -s "$W/save/tcc-$k" "$W/save/tcc-$((k-1))"; then
            say "fixed point: musl-$k = musl-$((k-1)), tcc-$k = tcc-$((k-1))"; break
        fi
    done
    cmp -s "$W/save/libc-$k.a" "$W/save/libc-$((k-1)).a" || fail "musl did not reach a fixed point"
    cmp -s "$W/save/tcc-$k" "$W/save/tcc-$((k-1))" || fail "tcc did not reach a fixed point"
    say "tcc-musl: $TC/bin/tcc"
    (cd /tmp && "$TC/bin/tcc" "$TESTS/libc-test.c" -o "$W/save/libc-test" -lm) > "$LOG/libc-test.log" 2>&1 \
        && "$W/save/libc-test" >> "$LOG/libc-test.log" 2>&1 || fail "libc-test (see $LOG/libc-test.log)"
    say "libc-test: $(tail -1 "$LOG/libc-test.log")"
    checkguard_probes; t_end stage2
}

# --- stage 3: tcc's tests2 -------------------------------------------------------------
# tests2 TCC RUNDIR NAME EXPECTED-FAILS: the tests/tests2 Makefile's rules (SKIP list
# for x86_64, ARGS, FLAGS, diff -b against .expect), except that every test is
# compiled to an executable and run, because -run needs dlsym, which a static libc
# lacks.  The list of failures must be exactly EXPECTED-FAILS.
tests2() {
    local tcc=$1 rundir=$2 name=$3 want=$4
    local d=$W/src/tcc/tests/tests2 pass=0 fail=0 f b o fl
    local res=$LOG/tests2-$name.txt out=$W/tmp-tests2; : > "$res"; rm -rf "$out"; mkdir -p "$out"
    for f in "$d"/[0-9]*.c; do
        b=$(basename "$f" .c)
        case $b in 34_array_assignment|73_arm64|98_al_ax_extend|99_fastcall) continue ;; esac
        fl=""; case $b in 76_dollars_in_identifiers) fl=-fdollars-in-identifiers ;;
                          60_errors_and_warnings|96_nodata_wanted) fl=-dt ;; esac
        o=$out/$b.output
        (
            cd "$rundir"
            if [ "$fl" = -dt ]; then
                timeout 60 "$tcc" $fl -run "$f"
            elif timeout 60 "$tcc" -static $fl "$f" -o "$out/$b.exe"; then
                cd "$d"
                case $b in
                    31_args) timeout 20 "$out/$b.exe" arg1 arg2 arg3 arg4 arg5 ;;
                    46_grep) timeout 20 "$out/$b.exe" '[^* ]*[:a:d: ]+\:\*-/: $' "$d/46_grep.c" ;;
                    *) timeout 20 "$out/$b.exe" ;;
                esac
            fi
        ) 2>&1 | sed "s,$d/,,g" > "$o" || true
        if diff -Nbu "$d/$b.expect" "$o" > "$out/$b.diff" 2>&1; then
            pass=$((pass+1)); echo "PASS $b" >> "$res"
        else
            fail=$((fail+1)); echo "FAIL $b" >> "$res"
        fi
    done
    rm -rf "$out"
    say "tests2 ($name): $pass passed, $fail failed of $((pass+fail)) (list: $res)"
    [ "$(sed -n 's/^FAIL //p' "$res" | tr '\n' ' ')" = "$want " ] \
        || fail "tests2 ($name): the failures are not exactly: $want"
}
stage3() {
    t_start stage3
    tests2 "$K/build/tcc-boot2" "$K" portable_libc "22_floating_point 23_type_coercion 24_math_library 28_strings 40_stdio 46_grep 49_bracket_evaluation 60_errors_and_warnings 70_floating_point_literals 81_types 82_attribs_position 83_utf8_in_identifiers 95_bitfields 95_bitfields_ms 96_nodata_wanted 97_utf8_string_literal"
    tests2 "$W/tc/bin/tcc" /tmp musl 96_nodata_wanted
    t_end stage3
}

# --- stage 4: binutils-2.30 built by tcc-musl -----------------------------------------
# Top-level configure with the tarball's pregenerated files (configure scripts,
# bison/flex outputs, opcodes tables); live-bootstrap regenerates all of these.
TCC_ENV() {  # sets TCCENV: the variables every autoconf run gets while tcc is the compiler
    local t=$W/tc/bin/tcc
    TCCENV=(CC="$t" CPP="$t -E" CXX=false CXXCPP="$t -E -xc" CC_FOR_BUILD="$t" CPP_FOR_BUILD="$t -E"
            CXX_FOR_BUILD=false AR="$t -ar" AR_FOR_BUILD="$t -ar" RANLIB=true RANLIB_FOR_BUILD=true)
}
# binutils-2.30's configuration, shared by stage 4 and the bridge
BU230_CONF=(--build=x86_64-unknown-linux-gnu --host=x86_64-unknown-linux-gnu
    --target=x86_64-unknown-linux-gnu --prefix="$W/bu" --with-sysroot= --disable-nls
    --disable-shared --enable-static --disable-gold --disable-plugins --disable-werror
    --enable-deterministic-archives --enable-64-bit-bfd --disable-gdb --disable-sim
    --disable-readline --disable-libdecnumber)
stage4() {
    t_start stage4
    need binutils-2.30.tar.xz
    local s=$W/src/binutils-2.30 b=$W/src/bu-build t=$W/tc/bin/tcc; TCC_ENV
    rm -rf "$s" "$b" "$W/bu"; tar -xJf "$D/binutils-2.30.tar.xz" -C "$W/src"; mkdir -p "$b"
    (
        cd "$b"
        # sub-configures run under make and would fall back to /lib/cpp for C++ (libtool)
        export CXXCPP="$t -E -xc"
        ../binutils-2.30/configure "${BU230_CONF[@]}" "${TCCENV[@]}" CFLAGS=-g0 lt_cv_sys_max_cmd_len=32768
        make -j"$JOBS" MAKEINFO=true
        make install MAKEINFO=true
    ) > "$LOG/binutils.log" 2>&1 || fail "binutils (see $LOG/binutils.log)"
    rm -rf "$s" "$b"
    local f; for f in as ld ar nm objcopy objdump; do say "binutils $f: $(sha "$W/bu/bin/$f")"; done
    # smoke tests: GNU ld links a tcc object against musl; GNU as agrees with tcc's
    # assembler on musl's fenv.s (original vs our .byte-encoded mxcsr instructions)
    local w=$W/tmp-bu; rm -rf "$w"; mkdir -p "$w"
    printf '#include <stdio.h>\nint main(){printf("ld ok %%lld\\n",1LL<<40);return 0;}\n' > "$w/h.c"
    "$t" -c "$w/h.c" -o "$w/h.o"
    "$W/bu/bin/ld" -static -o "$w/h" "$W/tc/lib/crt1.o" "$W/tc/lib/crti.o" "$w/h.o" "$W/tc/lib/libc.a" \
        "$W/tc/lib/tcc/libtcc1.a" "$W/tc/lib/libc.a" "$W/tc/lib/crtn.o"
    [ "$("$w/h")" = "ld ok 1099511627776" ] || fail "GNU ld smoke test"
    musl_src "$w/m"
    tar -xzf "$D/musl-1.1.24.tar.gz" -C "$w" musl-1.1.24/src/fenv/x86_64/fenv.s
    "$W/bu/bin/as" -o "$w/g.o" "$w/musl-1.1.24/src/fenv/x86_64/fenv.s"
    "$t" -c -o "$w/t.o" "$w/m/src/fenv/x86_64/fenv.s"
    for f in g t; do "$W/bu/bin/objdump" -d "$w/$f.o" | awk -F'\t' 'NF>=3{print $3}' \
        | sed 's/ *<.*//; s/[0-9a-f]* *$//; s/^\(j[a-z]*\|call[q]*\) .*/\1/' > "$w/$f.ins"; done
    cmp -s "$w/g.ins" "$w/t.ins" || fail "GNU as and tcc disagree on fenv.s"
    say "binutils smoke tests pass (ld links musl; as == tcc on fenv.s, $(wc -l < "$w/g.ins") insns)"
    rm -rf "$w"
    checkguard_probes; t_end stage4
}

# --- stage 5: flex (for gengtype-lex.l), sysroot, gcc-4.0.4 built by tcc ---------------
stage5() {
    t_start stage5
    need flex-2.6.4.tar.gz; TCC_ENV
    local s=$W/src/flex-2.6.4
    rm -rf "$s" "$W/tools"; tar -xzf "$D/flex-2.6.4.tar.gz" -C "$W/src"
    (
        cd "$s"
        ./configure --prefix="$W/tools" --disable-shared --disable-nls "${TCCENV[@]}"
        make -j"$JOBS"; make install
    ) > "$LOG/flex.log" 2>&1 || fail "flex (see $LOG/flex.log)"
    rm -rf "$s"
    grep -q -a -F "$W/hostbin/m4" "$W/tools/bin/flex" || fail "flex does not name $W/hostbin/m4"
    say "flex: $(sha "$W/tools/bin/flex") (execs $W/hostbin/m4, the host m4, at run time)"
    # sysroot = musl (built by tcc-musl) + the two libtcc1 objects its code calls
    # (__va_start/__va_arg, __floatundidf); tcc -ar cannot write empty archives, so the
    # empty libm.a etc. become valid empty archives
    local S=$W/sysroot
    rm -rf "$S"; mkdir -p "$S/usr/lib"; cp -r "$W/tc/include" "$S/usr/include"
    cp "$W/tc/lib/"*.a "$W/tc/lib/"*.o "$S/usr/lib/"
    for f in "$S/usr/lib/"*.a; do [ -s "$f" ] || printf '!<arch>\n' > "$f"; done
    cp "$W/tc/obj/libtcc1.o" "$W/src/tcc_libtcc1.o"; cp "$W/tc/obj/va_list.o" "$W/src/tcc_va_list.o"
    "$W/bu/bin/ar" rD "$S/usr/lib/libc.a" "$W/src/tcc_libtcc1.o" "$W/src/tcc_va_list.o"
    rm -rf "$W/g4" "$W/bridge"; need gcc-4.0.4-git-944765863e.tar
    PATH=$W/bu/bin:$PATH "$GCC64/build-gcc4.sh" "$W/tc/bin/tcc" "$W/g4" A > "$LOG/gcc4-A.log" 2>&1 \
        || fail "gcc-4.0.4 by tcc (see $LOG/gcc4-A.log)"
    local T=x86_64-unknown-linux-gnu
    say "gcc-A (tcc-built gcc-4.0.4) cc1: $(sha "$W/g4/libexec/gcc/$T/4.0.4/cc1")"
    PATH=$W/bu/bin:$PATH "$W/g4/bin/gcc" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-A" -lm
    "$W/src/lt-A" > "$LOG/libc-test-gccA.log" || fail "libc-test under gcc-A"
    say "gcc-A -O2 libc-test: $(tail -1 "$LOG/libc-test-gccA.log")"
    checkguard_probes; t_end stage5
}

# --- bridge: the direct route's GCC 4.0.4 in place of stages 0-5 --------------------------
# GCC64_DIRECT names a finished gcc-direct/stage-d.py WORK: GCC 4.0.4 whose first
# generation was compiled by the Forth compiler, at its stage 2 = 3 = 4 fixed point,
# with the stage-C musl sysroot and Forth-built binutils-2.30 it was configured with.
# GCC64_OYACC and GCC64_FLEX name the Forth-built oyacc and flex 2.5.11 (lexers.py).
# The bridge leaves stage 6 onward exactly the layout stages 4 and 5 leave:
#   bu/       binutils-2.30, BU230_CONF as in stage 4, built by the direct GCC
#   tools/    oyacc and flex 2.5.11, copied (they replace host bison and flex-2.6.4)
#   sysroot/  the direct route's musl (stage C), copied; stage 7 rebuilds it anyway
#   g4/       gcc-4.0.4 "gcc-A" by build-gcc4.sh, built by the direct GCC
# No tcc and no host parser generator.  bridge/inputs.txt records the inputs and their
# sha256.  bridge/direct.env marks a bridged BUILDROOT: while it exists stage 6 uses
# oyacc and flex 2.5.11 too, and the pins step skips what route D builds differently.
BRIDGE_ENV=$W/bridge/direct.env
bridge_env() {  # stage 6 after the bridge: the same parser generators as the bridge
    [ -f "$BRIDGE_ENV" ] || return 0
    export GCC4_YACC=$W/tools/bin/oyacc GCC4_LEX=$W/tools/bin/flex GCC4_BYACC=1
}
bridge() {
    t_start bridge
    local DW=${GCC64_DIRECT:?bridge needs GCC64_DIRECT=a finished gcc-direct/stage-d.py WORK}
    local Y=${GCC64_OYACC:?bridge needs GCC64_OYACC=the Forth-built oyacc}
    local X=${GCC64_FLEX:?bridge needs GCC64_FLEX=the Forth-built flex 2.5.11}
    local DT0=x86_64-pc-linux-gnu f h got
    DW=$(cd "$DW" && pwd)
    local G=$DW/prefix/bin/gcc
    grep -q '"fixed_point": true' "$DW/report.json" 2>/dev/null || fail "$DW/report.json: no stage-D fixed point"
    local SC; SC=$(sed -n 's/^  "stage_c": "\(.*\)",$/\1/p' "$DW/report.json")
    local DTC=$SC/toolchain
    [ -d "$SC/sysroot/usr/lib" ] && [ -x "$DTC/as" ] && [ -x "$DTC/ld" ] || fail "stage C $SC: no sysroot or toolchain"
    # stage 2 (prefix/) must be the fixed point stage-D's report recorded for stage 4
    for f in bin/gcc libexec/gcc/$DT0/4.0.4/cc1 libexec/gcc/$DT0/4.0.4/collect2; do
        h=$(grep -F "\"$f\": " "$DW/report.json" | sed 's/.*: "\([0-9a-f]*\)".*/\1/')
        got=$(sha "$DW/prefix/$f")
        [ -n "$h" ] && [ "$got" = "$h" ] || fail "direct $f is $got, not stage-D's fixed point ${h:-(unrecorded)}"
    done
    [ "$("$G" -dumpversion)" = 4.0.4 ] || fail "$G is not gcc-4.0.4"
    rm -rf "$W/bridge" "$W/bu" "$W/tools" "$W/sysroot" "$W/g4"; mkdir -p "$W/bridge" "$W/tools/bin" "$W/src"
    {
        echo "# bridge inputs: the direct route (gcc-direct/stage-d.py), $(date -u +%FT%TZ)"
        echo "stage_d $DW"; echo "stage_c $SC"
        for f in "$G" "$DW/prefix/libexec/gcc/$DT0/4.0.4/cc1" "$DTC/as" "$DTC/ld" "$DTC/ar" "$Y" "$X"; do
            echo "sha256 $(sha "$f") $f"
        done
    } > "$W/bridge/inputs.txt"
    cp "$Y" "$W/tools/bin/oyacc"; cp "$X" "$W/tools/bin/flex"
    say "direct gcc-4.0.4 (stage-D fixed point) cc1: $(sha "$DW/prefix/libexec/gcc/$DT0/4.0.4/cc1")"
    say "oyacc: $(sha "$W/tools/bin/oyacc")  flex-2.5.11: $(sha "$W/tools/bin/flex")"
    # binutils-2.30 into bu/, configured as stage 4, compiled by the direct GCC (which
    # assembles and links with the Forth-built binutils it was configured with)
    need binutils-2.30.tar.xz
    local s=$W/src/binutils-2.30 b=$W/src/bu-build
    rm -rf "$s" "$b"; tar -xJf "$D/binutils-2.30.tar.xz" -C "$W/src"; mkdir -p "$b"
    (
        cd "$b"
        export CXXCPP="$G -E -xc"
        PATH=$DTC:$PATH ../binutils-2.30/configure "${BU230_CONF[@]}" CC="$G" CPP="$G -E" CXX=false \
            CC_FOR_BUILD="$G" CPP_FOR_BUILD="$G -E" CXX_FOR_BUILD=false AR="$DTC/ar" RANLIB="$DTC/ranlib" \
            NM="$DTC/nm" CFLAGS=-g0
        PATH=$DTC:$PATH make -j"$JOBS" MAKEINFO=true
        PATH=$DTC:$PATH make install MAKEINFO=true
    ) > "$LOG/binutils.log" 2>&1 || fail "binutils by the direct gcc (see $LOG/binutils.log)"
    rm -rf "$s" "$b"
    for f in as ld ar nm objcopy objdump strip ranlib; do
        [ -x "$W/bu/bin/$f" ] || fail "binutils: no bu/bin/$f"
    done
    say "binutils-2.30 by the direct gcc: as $(sha "$W/bu/bin/as")  ld $(sha "$W/bu/bin/ld")"
    # sysroot: the direct route's musl-1.1.24, as stage C installed it
    cp -a "$SC/sysroot" "$W/sysroot"
    say "sysroot: direct musl libc.a $(sha "$W/sysroot/usr/lib/libc.a")"
    # gcc-A: the same build-gcc4.sh as stage 5, with the direct GCC as CC
    : > "$BRIDGE_ENV"; bridge_env
    need gcc-4.0.4-git-944765863e.tar
    PATH=$W/bu/bin:$PATH "$GCC64/build-gcc4.sh" "$G" "$W/g4" A > "$LOG/gcc4-A.log" 2>&1 \
        || fail "gcc-4.0.4 by the direct gcc (see $LOG/gcc4-A.log)"
    local T=x86_64-unknown-linux-gnu
    say "gcc-A (gcc-4.0.4 built by the direct gcc) cc1: $(sha "$W/g4/libexec/gcc/$T/4.0.4/cc1")"
    PATH=$W/bu/bin:$PATH "$W/g4/bin/gcc" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-A" -lm
    "$W/src/lt-A" > "$LOG/libc-test-gccA.log" || fail "libc-test under gcc-A"
    say "gcc-A -O2 libc-test: $(tail -1 "$LOG/libc-test-gccA.log")"
    checkguard_probes; t_end bridge
}

# --- stage 6: gcc-4.0.4 builds itself twice; B = C ---------------------------------------
stage6() {
    t_start stage6
    local T=x86_64-unknown-linux-gnu f
    need gcc-4.0.4-git-944765863e.tar
    rm -rf "$W/g4s" "$W/destC"; bridge_env
    PATH=$W/bu/bin:$PATH "$GCC64/build-gcc4.sh" "$W/g4/bin/gcc" "$W/g4s" B > "$LOG/gcc4-B.log" 2>&1 \
        || fail "gcc-B (see $LOG/gcc4-B.log)"
    PATH=$W/bu/bin:$PATH "$GCC64/build-gcc4.sh" "$W/g4s/bin/gcc" "$W/g4s" C "$W/destC" > "$LOG/gcc4-C.log" 2>&1 \
        || fail "gcc-C (see $LOG/gcc4-C.log)"
    for f in bin/gcc bin/cpp libexec/gcc/$T/4.0.4/cc1 libexec/gcc/$T/4.0.4/collect2 \
             lib/gcc/$T/4.0.4/libgcc.a lib/gcc/$T/4.0.4/crtbegin.o lib/gcc/$T/4.0.4/crtend.o; do
        cmp -s "$W/g4s/$f" "$W/destC$W/g4s/$f" || fail "gcc-B and gcc-C differ in $f"
        say "gcc-B = gcc-C: $f $(sha "$W/g4s/$f")"
    done
    rm -rf "$W/destC" "$W/src/gcc-4.0.4-work"
    PATH=$W/bu/bin:$PATH "$W/g4s/bin/gcc" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-B" -lm
    "$W/src/lt-B" > "$LOG/libc-test-gccB.log" || fail "libc-test under gcc-B"
    say "gcc-B -O2 libc-test: $(tail -1 "$LOG/libc-test-gccB.log")"
    checkguard_probes; t_end stage6
}

# --- stage 7: musl rebuilt by gcc-4.0.4 (pristine source + GNU as), gmp/mpfr/mpc ---------
GB=$W/bu/bin
gnu_env() {  # gnu_env CC -- sets GNUENV: autoconf variables for a gcc + binutils-2.30 build
    GNUENV=(CC="$1" CPP="$1 -E" AR=$GB/ar NM=$GB/nm RANLIB=$GB/ranlib AS=$GB/as LD=$GB/ld
            OBJDUMP=$GB/objdump STRIP=$GB/strip OBJCOPY=$GB/objcopy)
}
stage7() {
    t_start stage7
    local C=$W/g4s/bin/gcc U=$W/sysroot/usr T=x86_64-unknown-linux-gnu s
    need musl-1.1.24.tar.gz
    s=$W/src/musl-gcc; rm -rf "$s" "$s.tmp"; mkdir "$s.tmp"
    tar -xzf "$D/musl-1.1.24.tar.gz" -C "$s.tmp"; mv "$s.tmp/musl-1.1.24" "$s"; rmdir "$s.tmp"
    patch -s -p1 -F0 -d "$s" < "$PATCHES/musl-1.1.24/06-lb-madvise_preserve_errno.patch"
    for p in "$PATCHES"/musl-gcc/*.diff; do patch -s -p1 -F0 -d "$s" < "$p"; done
    rm -rf "$W/sysroot"
    ( cd "$s" && PATH=$GB:$PATH CC=$C ./configure --target=x86_64 --host=x86_64 --disable-shared \
          --prefix="$U" --syslibdir="$W/sysroot/lib" \
      && PATH=$GB:$PATH make -j"$JOBS" CROSS_COMPILE= AR=$GB/ar RANLIB=$GB/ranlib \
      && PATH=$GB:$PATH make install CROSS_COMPILE= AR=$GB/ar RANLIB=$GB/ranlib ) > "$LOG/musl-gcc.log" 2>&1 \
        || fail "musl by gcc-4.0.4 (see $LOG/musl-gcc.log)"
    rm -rf "$s"
    say "musl-1.1.24 by gcc-4.0.4: libc.a $(sha "$U/lib/libc.a")"
    PATH=$GB:$PATH "$C" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-m" -lm
    "$W/src/lt-m" > "$LOG/libc-test-muslgcc.log" || fail "libc-test with gcc-built musl"
    local name tarball dir extra; gnu_env "$C"
    for name in gmp mpfr mpc; do
        case $name in
            gmp)  tarball=gmp-6.2.1+dfsg.tar.xz; dir=gmp-6.2.1+dfsg; extra="CC_FOR_BUILD=$C" ;;
            mpfr) tarball=mpfr-4.1.0.tar.xz; dir=mpfr-4.1.0; extra="--with-gmp=$U" ;;
            mpc)  tarball=mpc-1.2.1.tar.gz; dir=mpc-1.2.1; extra="--with-gmp=$U --with-mpfr=$U" ;;
        esac
        need "$tarball"
        rm -rf "$W/src/$dir"; tar -xf "$D/$tarball" -C "$W/src"
        ( cd "$W/src/$dir" && PATH=$GB:$PATH env "${GNUENV[@]}" ./configure --build=$T --host=$T \
              --prefix="$U" --disable-shared --enable-static $extra \
          && PATH=$GB:$PATH make -j"$JOBS" && PATH=$GB:$PATH make install \
          && PATH=$GB:$PATH make -j"$JOBS" check ) > "$LOG/$name.log" 2>&1 || fail "$name (see $LOG/$name.log)"
        say "$name: $(grep -E '^# (PASS|FAIL):' "$LOG/$name.log" | awk '{s[$2]+=$3} END{printf "check PASS %d FAIL %d", s["PASS:"], s["FAIL:"]}')"
        rm -rf "$W/src/$dir"
    done
    checkguard_probes; t_end stage7
}

# --- stage 8: gcc-4.7.4 (C, C++) built by gcc-4.0.4 -----------------------------------------
stage8() {
    t_start stage8
    local T=x86_64-linux-musl
    rm -rf "$W/g47"; need gcc-4.7.4.tar.xz; need binutils-2.41.tar.xz
    PATH=$GB:$PATH "$GCC64/build-gcc47.sh" "$W/g4s/bin/gcc" "$W/g47" > "$LOG/gcc47-A.log" 2>&1 \
        || fail "gcc-4.7.4 (see $LOG/gcc47-A.log)"
    say "gcc-4.7.4 cc1: $(sha "$W/g47/libexec/gcc/$T/4.7.4/cc1")  cc1plus: $(sha "$W/g47/libexec/gcc/$T/4.7.4/cc1plus")"
    PATH=$GB:$PATH "$W/g47/bin/gcc" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-47" -lm
    PATH=$GB:$PATH "$W/g47/bin/g++" -O2 "$TESTS/cxx-test.cc" -o "$W/src/cxx-47"
    "$W/src/lt-47" > "$LOG/libc-test-gcc47.log" && "$W/src/cxx-47" > "$LOG/cxx-test-gcc47.log" \
        || fail "gcc-4.7.4 tests"
    say "gcc-4.7.4: $(tail -1 "$LOG/libc-test-gcc47.log"); $(tail -1 "$LOG/cxx-test-gcc47.log")"
    rm -rf "$W/src/gcc-4.7.4" "$W/src/g47-build"
    checkguard_probes; t_end stage8
}

# --- stage 9: binutils-2.41 built by gcc-4.7.4 -----------------------------------------------
stage9() {
    t_start stage9
    local C=$W/g47/bin/gcc X=$W/g47/bin/g++ b=$W/src/bu2-build; gnu_env "$C"
    need binutils-2.41.tar.xz
    rm -rf "$W/src/binutils-2.41" "$b" "$W/bu2"; tar -xJf "$D/binutils-2.41.tar.xz" -C "$W/src"; mkdir "$b"
    ( cd "$b" && PATH=$GB:$PATH env "${GNUENV[@]}" CXX="$X" CC_FOR_BUILD="$C" CXX_FOR_BUILD="$X" \
          ../binutils-2.41/configure --build=x86_64-linux-musl --host=x86_64-linux-musl \
          --target=x86_64-linux-musl --prefix="$W/bu2" --with-sysroot= --disable-nls --disable-shared \
          --enable-static --disable-gold --disable-gprofng --disable-plugins --disable-werror \
          --enable-deterministic-archives --enable-64-bit-bfd --disable-gdb --disable-gdbserver \
          --disable-sim --disable-readline --disable-libdecnumber --without-zstd --without-debuginfod \
          MAKEINFO=true \
      && PATH=$GB:$PATH make -j"$JOBS" MAKEINFO=true && PATH=$GB:$PATH make install MAKEINFO=true ) \
        > "$LOG/binutils-2.41.log" 2>&1 || fail "binutils-2.41 (see $LOG/binutils-2.41.log)"
    rm -rf "$W/src/binutils-2.41" "$b"
    say "binutils-2.41 as: $(sha "$W/bu2/bin/as")  ld: $(sha "$W/bu2/bin/ld")"
    checkguard_probes; t_end stage9
}

# --- stage 10: gcc-10.5.0 (C, C++) built by gcc-4.7.4 + binutils-2.41 ----------------------------
stage10() {
    t_start stage10
    local T=x86_64-linux-musl
    rm -rf "$W/g10"; need gcc-10.5.0.tar.xz
    PATH=$W/bu2/bin:$PATH "$GCC64/build-gcc10.sh" "$W/g47/bin/gcc" "$W/g47/bin/g++" "$W/g10" > "$LOG/gcc10-A.log" 2>&1 \
        || fail "gcc-10.5.0 (see $LOG/gcc10-A.log)"
    say "gcc-10.5.0 cc1: $(sha "$W/g10/libexec/gcc/$T/10.5.0/cc1")  cc1plus: $(sha "$W/g10/libexec/gcc/$T/10.5.0/cc1plus")"
    PATH=$W/bu2/bin:$PATH "$W/g10/bin/gcc" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-10" -lm
    PATH=$W/bu2/bin:$PATH "$W/g10/bin/g++" -O2 -Wno-deprecated-declarations "$TESTS/cxx-test.cc" -o "$W/src/cxx-10"
    "$W/src/lt-10" > "$LOG/libc-test-gcc10.log" && "$W/src/cxx-10" > "$LOG/cxx-test-gcc10.log" \
        || fail "gcc-10.5.0 tests"
    say "gcc-10.5.0: $(tail -1 "$LOG/libc-test-gcc10.log"); $(tail -1 "$LOG/cxx-test-gcc10.log")"
    rm -rf "$W/src/gcc-10.5.0" "$W/src/g10-build"
    checkguard_probes; t_end stage10
}

# --- stage 11: gcc-15.2.0 (C, C++), full 3-stage bootstrap seeded by gcc-10.5.0 -------------------
stage11() {
    t_start stage11
    local T=x86_64-linux-musl
    need gcc-15.2.0.tar.xz
    rm -rf "$W/g15"
    PATH=$W/bu2/bin:$PATH "$GCC64/build-gcc15.sh" "$W/g10/bin/gcc" "$W/g10/bin/g++" "$W/g15" > "$LOG/gcc15.log" 2>&1 \
        || fail "gcc-15.2.0 (see $LOG/gcc15.log)"
    grep -q "Comparison successful" "$LOG/gcc15.log" || fail "gcc-15 bootstrap: no 'Comparison successful'"
    say "gcc-15.2.0 bootstrap: stage2 = stage3 ($(grep -c '^Comparing stages' "$LOG/gcc15.log") comparison)"
    say "gcc-15.2.0 cc1: $(sha "$W/g15/libexec/gcc/$T/15.2.0/cc1")  cc1plus: $(sha "$W/g15/libexec/gcc/$T/15.2.0/cc1plus")"
    PATH=$W/bu2/bin:$PATH "$W/g15/bin/gcc" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-15" -lm
    PATH=$W/bu2/bin:$PATH "$W/g15/bin/g++" -O2 -Wno-deprecated-declarations "$TESTS/cxx-test.cc" -o "$W/src/cxx-15"
    "$W/src/lt-15" > "$LOG/libc-test-gcc15.log" && "$W/src/cxx-15" > "$LOG/cxx-test-gcc15.log" || fail "gcc-15 tests"
    say "gcc-15.2.0: $(tail -1 "$LOG/libc-test-gcc15.log"); $(tail -1 "$LOG/cxx-test-gcc15.log")"
    rm -rf "$W/src/gcc-15.2.0" "$W/src/g15-build"
    checkguard_probes; t_end stage11
}

# --- stage 12: verify every compiler in the chain ----------------------------------------
# hello (static), 64-bit arithmetic, floating point (double, long double, libm),
# C++ (exceptions, iostream, templates) where the gcc has it; the final gcc also
# at -O2 with -v, and its sysroot/as/ld must be the chain's.
stage12() {
    t_start stage12
    local w=$W/src/verify n cc bin out
    rm -rf "$w"; mkdir -p "$w"
    for n in g4 g4s g47 g10 g15; do
        cc=$W/$n/bin/gcc; bin=$GB; case $n in g10|g15) bin=$W/bu2/bin ;; esac
        for t in hello t64 flt; do
            PATH=$bin:$PATH "$cc" -O2 -static "$TESTS/$t.c" -o "$w/$n-$t" -lm || fail "$n: $t.c does not compile"
            out=$("$w/$n-$t") || fail "$n: $t runs but fails: $out"
            say "verify $n $t: $out"
        done
        case $n in g47|g10|g15)
            PATH=$bin:$PATH "$W/$n/bin/g++" -O2 -static -Wno-deprecated-declarations -Wno-unused-result "$TESTS/cxx-test.cc" -o "$w/$n-cxx" \
                || fail "$n: C++ test does not compile"
            out=$("$w/$n-cxx") || fail "$n: C++ test runs but fails: $out"
            say "verify $n c++: $out" ;;
        esac
    done
    # final gcc: -O2 -v; everything it runs must come from the chain
    cc=$W/g15/bin/gcc
    PATH=$W/bu2/bin:$PATH "$cc" -v -O2 -static "$TESTS/hello.c" -o "$w/final-hello" > "$w/final-v.txt" 2>&1 \
        || fail "gcc-15 -v -O2 hello"
    "$w/final-hello" > /dev/null || fail "gcc-15 -O2 hello does not run"
    say "gcc-15 version: $("$cc" -dumpfullversion) target $("$cc" -dumpmachine)"
    say "gcc-15 sysroot: $("$cc" -print-sysroot)"
    say "gcc-15 as: $("$cc" -print-prog-name=as)  ld: $("$cc" -print-prog-name=ld)"
    [ "$("$cc" -print-sysroot)" = "$W/sysroot" ] || fail "gcc-15 sysroot is not the chain's"
    [ "$("$cc" -print-prog-name=as)" = "$W/bu2/bin/as" ] || fail "gcc-15 as is not binutils-2.41 from the chain"
    [ "$("$cc" -print-prog-name=ld)" = "$W/bu2/bin/ld" ] || fail "gcc-15 ld is not binutils-2.41 from the chain"
    # every absolute program path in the -v trace lies under $W, or is a test source
    grep -oE '^ ?/[^ ]+' "$w/final-v.txt" | sed 's/^ //' | grep -v "^$TESTS/" | sort -u > "$w/final-progs.txt"
    if grep -v "^$W/" "$w/final-progs.txt"; then fail "gcc-15 -v ran something outside the chain"; fi
    say "gcc-15 -v ran only: $(tr '\n' ' ' < "$w/final-progs.txt" | sed "s,$W/,,g")"
    checkguard_probes; t_end stage12
}

# --- pins: sha256 of every stage's key outputs vs gcc64/HASHES ----------------------------
# HASHES lists "SHA256  FILE  SCOPE".  SCOPE "any": the file must have that hash
# whatever BUILDROOT is.  SCOPE "root": the file embeds absolute paths under
# BUILDROOT, so the hash holds only when BUILDROOT is the one on HASHES's "root" line
# (the canonical run's); elsewhere it is reported, not enforced.  Files a partial
# run did not build are skipped.
hashes() {
    local line h f scope root got n_ok=0 n_skip=0 n_bad=0 n_d=0
    : > "$LOG/hashes.txt"
    root=$(sed -n 's/^root //p' "$GCC64/HASHES")
    local bridged=0; [ -f "$BRIDGE_ENV" ] && bridged=1
    while read -r h f scope; do
        case $h in ''|'#'*|root) continue ;; esac
        [ -f "$W/$f" ] || continue
        # SCOPE "direct": the file's value after the bridge, at the canonical BUILDROOT; it
        # replaces the file's "root" line there (see gcc64/README.md, "Bridge")
        if [ "$scope" = direct ]; then [ "$bridged" = 1 ] || continue; scope=root
        elif [ "$bridged" = 1 ] && grep -q "  $f  direct\$" "$GCC64/HASHES"; then continue; fi
        got=$(sha "$W/$f"); echo "$got  $f" >> "$LOG/hashes.txt"
        # after the bridge, the TinyCC route's own outputs, and executables that link in
        # route D's musl or are built by different compilers or parser generators, differ by
        # design; everything compiled by gcc-B (libgcc, crt*, sysroot) and later must not
        if [ "$bridged" = 1 ]; then
            case $f in tccboot/*|p0/*|tc/*|m1/*|t1/*|bu/*|tools/*|g4/*|g4s/bin/*|g4s/libexec/*)
                n_d=$((n_d+1)); echo "  (route D: $f not comparable)" >> "$LOG/hashes.txt"; continue ;;
            esac
        fi
        if [ "$scope" = root ] && [ "$W" != "$root" ]; then
            n_skip=$((n_skip+1))
        elif [ "$got" = "$h" ]; then
            n_ok=$((n_ok+1))
        else
            n_bad=$((n_bad+1)); echo "$me: $f is $got, not the pinned $h ($scope)" >&2
        fi
    done < "$GCC64/HASHES"
    local why=""; [ "$n_skip" = 0 ] || why=" (BUILDROOT is not $root)"
    [ "$n_d" = 0 ] || why="$why; $n_d built differently by route D (bridge)"
    say "pins: $n_ok as pinned, $n_bad differ, $n_skip path-dependent and not comparable here$why; all in $LOG/hashes.txt"
    if [ "$n_bad" != 0 ]; then
        [ "${GCC64_REPIN:-0}" = 1 ] && { say "GCC64_REPIN=1: not failing; new values in $LOG/hashes.txt"; return 0; }
        fail "$n_bad artifact(s) differ from gcc64/HASHES"
    fi
}

stages=("$@")
if [ ${#stages[@]} = 0 ]; then
    if [ -n "${GCC64_DIRECT:-}" ]; then stages=(bridge stage6 stage7 stage8 stage9 stage10 stage11 stage12)
    else stages=(stage0 stage1 stage2 stage3 stage4 stage5 stage6 stage7 stage8 stage9 stage10 stage11 stage12); fi
fi
for s in "${stages[@]}"; do
    case $s in stage[0-9]|stage1[0-2]|bridge) ;; *) echo "$me: unknown stage '$s' (stage0 ... stage12, bridge)" >&2; exit 1 ;; esac
done
# Check selected stages' pinned sources up front. A stage4-10 Linux
# continuation must not require an unused GCC15 archive (or refetch stage0).
stage_sources() {
    case $1 in
        stage2) echo musl-1.1.24.tar.gz ;;
        stage4) echo binutils-2.30.tar.xz musl-1.1.24.tar.gz ;;
        stage5) echo flex-2.6.4.tar.gz gcc-4.0.4-git-944765863e.tar ;;
        stage6) echo gcc-4.0.4-git-944765863e.tar ;;
        bridge) echo binutils-2.30.tar.xz gcc-4.0.4-git-944765863e.tar ;;
        stage7) echo musl-1.1.24.tar.gz gmp-6.2.1+dfsg.tar.xz mpfr-4.1.0.tar.xz mpc-1.2.1.tar.gz ;;
        stage8) echo gcc-4.7.4.tar.xz binutils-2.41.tar.xz ;;
        stage9) echo binutils-2.41.tar.xz ;;
        stage10) echo gcc-10.5.0.tar.xz ;;
        stage11) echo gcc-15.2.0.tar.xz ;;
    esac
}
for s in "${stages[@]}"; do
    for f in $(stage_sources "$s"); do need "$f"; done
done
mkhostbin
export PATH="$W/guard:$W/hostbin"
mkguard
devnull() { [ -c /dev/null ] || fail "/dev/null is no longer a character device (after $1)"; }
devnull start
say "BUILDROOT=$W  GCC64_CACHE=$D  stages: ${stages[*]}"
for s in "${stages[@]}"; do "$s"; devnull "$s"; done
hashes
say "all requested stages passed"
