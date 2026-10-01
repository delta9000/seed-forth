# ladder/stage11.sh: binutils and GCC (gcc64 stages 4-10) inside the chain
# root, with only stage 10's tools on PATH.  tools/ladder.recipe's stage 8
# already built tcc-musl exactly as gcc64's stages 1-2 do (same pinned
# libc.a), so gcc64's tc/ is that build.
set -eu
export PATH=/usr/bin:/bin HOME=/ SHELL=/bin/sh LC_ALL=C TZ=UTC0 TAR_OPTIONS=--no-same-owner
# tcc -ar rewrites the archive, so libtool must never split an ar command.
export lt_cv_sys_max_cmd_len=1572864
B=/build-out/g64
mkdir -p $B $B/src
chmod 755 /gcc64/*.sh            # copied into the root as plain files
[ -e $B/tc ] || ln -s /build-out/pnut-amd64/gcc64/tc $B/tc
[ $# -gt 0 ] || set -- stage4 stage5 stage6 stage7 stage8 stage9 stage10
GCC64_CACHE=/build-out/distfiles BUILDROOT=$B JOBS=${JOBS:-16} \
    bash /gcc64/run-gcc64.sh "$@" || {
    # Show the failing stage's log on the console (it is inside the build).
    log=$(ls -t $B/logs/*.log 2>/dev/null | head -1)
    [ -n "$log" ] && { echo "=== tail of $log"; tail -n 60 "$log"; }
    exit 1
}
