#!/bin/sh
# Re-run tools/capture-build.py for every package in ladder/PACKAGES.
# Authoring only; needs host gcc-free tools (sh, make, strace) and the
# chain's tcc-musl.  Run from the repository root.  Usage:
#   tools/recapture-ladder.sh [NAME...]     (default: every package)
set -eu
cd "$(dirname "$0")/.."
TC="$PWD/build-out/pnut-amd64/gcc64/tc/bin/tcc"
WORK="$PWD/build-out/capture"          # scratch; one subdirectory per package
[ -x "$TC" ] || { echo "recapture: no tcc-musl at $TC" >&2; exit 1; }
ulimit -f 2097152                      # no single file over 2 GiB
mkdir -p "$WORK"
NC="--disable-nls --disable-dependency-tracking"

opts() {
    case $1 in
    make-3.82)     echo "--configure|$NC --without-guile|--install|make=bin/make" ;;
    gzip-1.13)     echo "--configure|$NC|--install|gzip=bin/gzip" ;;
    bash-5.2.37)   echo "--configure|$NC --without-bash-malloc --enable-static-link|--install|bash=bin/bash" ;;
    tar-1.35)      echo "--configure|$NC --disable-acl --without-selinux --without-posix-acls|--install|src/tar=bin/tar" ;;
    sed-4.9)       echo "--configure|$NC --disable-acl --without-selinux|--install|sed/sed=bin/sed" ;;
    grep-3.11)     echo "--configure|$NC --disable-perl-regexp|--install|src/grep=bin/grep" ;;
    gawk-5.3.1)    echo "--configure|$NC --disable-extensions --disable-mpfr --without-readline|--install|gawk=bin/gawk" ;;
    coreutils-9.5) echo "--configure|$NC --disable-acl --disable-xattr --without-selinux --without-openssl --without-gmp --disable-libcap --enable-no-install-program=stdbuf|--install-dir|src=bin" ;;
    patch-2.7.6)   echo "--configure|$NC --disable-xattr|--install|src/patch=bin/patch" ;;
    xz-5.6.3)      echo "--configure|$NC --disable-shared --disable-threads --disable-doc --disable-scripts --disable-lzmadec --disable-lzmainfo --disable-xzdec|--install|src/xz/xz=bin/xz" ;;
    *) echo "recapture: no options for $1" >&2; exit 1 ;;
    esac
}

if [ $# -eq 0 ]; then
    set -- $(awk '!/^#/ && NF {print $1}' ladder/PACKAGES)
fi
for name in "$@"; do
    IFS='|' read -r f1 v1 f2 v2 <<EOF
$(opts "$name")
EOF
    PATH=/usr/bin:$PATH timeout 2400 python3 tools/capture-build.py "$name" \
        "build-out/distfiles/$name.tar.gz" --cc "$TC" --keep "$WORK/$name" \
        "$f1" "$v1" "$f2" "$v2" | tail -1
done
