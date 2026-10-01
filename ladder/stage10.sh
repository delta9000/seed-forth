# ladder/stage10.sh: the ladder with a shell.  Run by tools/chain-root.sh
# inside the chain root as  bash /ladder/stage10.sh  (no environment is
# passed in; everything is set here).  Every program it runs was built by
# the chain: tools/amd64.recipe (tcc), tools/ladder.recipe (musl, tcc-musl,
# and the ten replayed tools in /build-out/pnut-amd64/usr).
set -eu
W=/build-out/pnut-amd64
U=$W/usr
TC=$W/gcc64/tc
D=/build-out/distfiles
S=/build-out/s10                        # sources and builds
P=/usr                                  # where stage 10 installs
LOG=/build-out/s10-logs

# The chain's tools at the usual paths, so #!/bin/sh and configure work.
if [ ! -e /bin/sh ]; then
    $U/bin/mkdir -p /usr/bin /bin /usr/lib /usr/include
    for f in $U/bin/*; do $U/bin/cp "$f" /usr/bin/; done
    /usr/bin/cp $TC/bin/tcc /usr/bin/tcc
    /usr/bin/ln -s /usr/bin/bash /bin/sh
    /usr/bin/ln -s /usr/bin/bash /bin/bash
    /usr/bin/ln -s /usr/bin/env /usr/bin/env.real 2>/dev/null || true
    /usr/bin/printf '#!/bin/sh\nexec /usr/bin/tcc -ar "$@"\n' > /usr/bin/ar
    /usr/bin/printf '#!/bin/sh\nexit 0\n' > /usr/bin/ranlib
    /usr/bin/printf '#!/bin/sh\nexec /usr/bin/tcc "$@"\n' > /usr/bin/ld
    /usr/bin/chmod 755 /usr/bin/ar /usr/bin/ranlib /usr/bin/ld
fi
export PATH=/usr/bin:/bin HOME=/ SHELL=/bin/sh LC_ALL=C TZ=UTC0 TAR_OPTIONS=--no-same-owner
# tcc -ar rewrites the archive, so libtool must never split an ar command.
export lt_cv_sys_max_cmd_len=1572864
export CC=tcc CC_FOR_BUILD=tcc BUILD_CC=tcc LD=ld AR=ar RANLIB=ranlib CFLAGS=-O2 SOURCE_DATE_EPOCH=0
mkdir -p "$S" "$LOG"

say() { echo "stage10: $*"; }
fail() {
    echo "stage10: FAIL: $*" >&2
    # The log named in the message is inside the build: show its end.
    log=$(echo "$*" | sed -n 's/.*(see \(.*\))$/\1/p')
    [ -n "$log" ] && [ -f "$log" ] && {
        echo "=== errors in $log" >&2; grep -n -E 'error|Error [0-9]|No such|not found' "$log" | head -n 30 >&2
        echo "=== tail of $log" >&2; tail -n 30 "$log" >&2; }
    exit 1
}

# unpack NAME TARBALL SHA256: fresh $S/NAME from a pinned tarball
unpack() {
    echo "$3  $D/$2" | sha256sum -c --quiet || fail "sha256 $2"
    rm -rf "$S/$1"
    mkdir -p "$S/$1.tmp"
    tar --no-same-owner -xf "$D/$2" -C "$S/$1.tmp"
    mv "$S/$1.tmp"/* "$S/$1"
    rmdir "$S/$1.tmp"
}

# gnu NAME TARBALL SHA256 [configure args...]: apply patches/ladder/NAME/*.diff,
# then configure, make, make install.  HELP2MAN and MAKEINFO are no-ops: the
# tarballs' man and info pages are used as shipped (help2man needs perl).
gnu() {
    name=$1 tarball=$2 sha=$3; shift 3
    local mk=("${MKARGS[@]}")
    MKARGS=()
    if [ -e "$LOG/$name.done" ]; then return 0; fi
    unpack "$name" "$tarball" "$sha"
    for pt in /patches/ladder/$name/*.diff; do
        [ -e "$pt" ] || continue
        patch -d "$S/$name" -p1 -F0 < "$pt" > /dev/null || fail "patch $pt"
    done
    ( cd "$S/$name" &&
      ./configure --prefix=$P --disable-nls "$@" &&
      make -j"${JOBS:-8}" HELP2MAN=true MAKEINFO=true "${mk[@]}" &&
      make install HELP2MAN=true MAKEINFO=true "${mk[@]}" ) > "$LOG/$name.log" 2>&1 || fail "$name (see $LOG/$name.log)"
    touch "$LOG/$name.done"
    say "$name"
}
MKARGS=()          # extra make arguments for the next gnu call only

gnu make-4.4.1 make-4.4.1.tar.gz dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3 \
    --without-guile
make --version | head -1

# bzip2 has no configure: its Makefile, then install into $P.
if [ ! -e "$LOG/bzip2-1.0.8.done" ]; then
    unpack bzip2-1.0.8 bzip2-1.0.8.tar.gz ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269
    ( cd "$S/bzip2-1.0.8" && make CC=tcc AR=ar RANLIB=ranlib CFLAGS="-O2 -D_FILE_OFFSET_BITS=64" \
        bzip2 bzip2recover && make install PREFIX=$P CC=tcc AR=ar RANLIB=ranlib ) \
        > "$LOG/bzip2-1.0.8.log" 2>&1 || fail "bzip2 (see $LOG/bzip2-1.0.8.log)"
    touch "$LOG/bzip2-1.0.8.done"; say bzip2-1.0.8
fi
# The replayed grep, gzip and xz lack egrep/fgrep, gunzip/zcat and unxz:
# rebuild them the ordinary way.
gnu grep-3.11 grep-3.11.tar.gz 1f31014953e71c3cddcedb97692ad7620cb9d6d04fbdc19e0d8dd836f87622bb \
    --disable-perl-regexp
gnu gzip-1.13 gzip-1.13.tar.gz 20fc818aeebae87cdbf209d35141ad9d3cf312b35a5e6be61bfcfbf9eddd212a
gnu xz-5.6.3 xz-5.6.3.tar.gz b1d45295d3f71f25a4c9101bd7c8d16cb56348bbef3bbc738da0351e17c73317 \
    --disable-shared --disable-threads --disable-doc
MKARGS=("SUBDIRS=lib src")         # man/ runs its own help2man (perl)
gnu diffutils-3.10 diffutils-3.10.tar.xz 90e5e93cc724e4ebe12ede80df1634063c7a855692685919bfe60b556c9bd09e
gnu findutils-4.10.0 findutils-4.10.0.tar.xz 1387e0b67ff247d2abde998f90dfbf70c1491391a59ddfecb8ae698789f0a4f5
gnu m4-1.4.19 m4-1.4.19.tar.gz 3be4a26d825ffdfda52a56fc43246456989a3630093cced3fbddf4771ee58a70
gnu bison-3.8.2 bison-3.8.2.tar.gz 06c9e13bdf7eb24d4ceb6b59205a4f67c2c7e7213119644430fe82fbd14a0abb
gnu flex-2.6.4 flex-2.6.4.tar.gz e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995 \
    --disable-shared
gnu bc-1.07.1 bc-1.07.1.tar.gz 62adfca89b0a1c0164c2cdca59ca210c1d44c3ffc46daf9931cf4942664cb02a
# Two answers gcc64's scripts ask the system for.
printf '#!/bin/sh\necho chain-root\n' > $P/bin/hostname
cp /ladder/getconf.sh $P/bin/getconf
cp /ladder/which.sh $P/bin/which
[ -e $P/bin/awk ] || ln -s gawk $P/bin/awk
[ -e $P/bin/install ] || ln -s ginstall $P/bin/install
chmod 755 $P/bin/hostname $P/bin/getconf $P/bin/which
say "environment ready"
