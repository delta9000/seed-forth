#!/bin/bash
# build-gcc47.sh CC PREFIX [DESTDIR] -- gcc-4.7.4 (C, C++) for x86_64-linux-musl,
# live-bootstrap's patches, against $W/sysroot (musl + gmp/mpfr/mpc there).
set -euo pipefail
W=${GCC64_W:?run via gcc64/run-gcc64.sh} DIST=${GCC64_CACHE:?} PATCHES=${GCC64_PATCHES:?}
CC=$1 P=$2 DEST=${3:-}
T=x86_64-linux-musl S=$W/sysroot U=$W/sysroot/usr B=$W/bu/bin
SRC=$W/src/gcc-4.7.4 BLD=$W/src/g47-build
rm -rf "$SRC" "$BLD"
tar -xJf "$DIST/gcc-4.7.4.tar.xz" -C "$W/src" --exclude='gcc-4.7.4/libjava' --exclude='gcc-4.7.4/gcc/testsuite' \
    --exclude='gcc-4.7.4/libgo' --exclude='gcc-4.7.4/gcc/go' --exclude='gcc-4.7.4/libgfortran' \
    --exclude='gcc-4.7.4/gcc/ada' --exclude='gcc-4.7.4/libada' --exclude='gcc-4.7.4/gnattools' \
    --exclude='gcc-4.7.4/gcc/java' --exclude='gcc-4.7.4/boehm-gc' --exclude='gcc-4.7.4/gcc/fortran' \
    --exclude='gcc-4.7.4/gcc/objc' --exclude='gcc-4.7.4/gcc/objcp' --exclude='gcc-4.7.4/libobjc'
cd "$SRC"
mkdir -p gcc/testsuite/gcc.target/i386     # lb's -mlong-double patch adds tests there
for p in "$PATCHES"/gcc-4.7.4/*.patch; do patch -s -p1 -F0 < "$p"; done   # = live-bootstrap steps/gcc-4.7.4/patches/*
tar -xJf "$DIST/binutils-2.41.tar.xz" -O binutils-2.41/config.sub > config.sub   # knows *-linux-musl
mkdir "$BLD"; cd "$BLD"
# CXX=false: libtool's C++ tag would fall back to /lib/cpp (host) in sub-configures run by make
export CXXCPP="$CC -E -x c"
# gcc_cv_*: what lb's regenerated gcc/configure (0005-musl-libc-config.patch) decides for musl
env CC="$CC" CPP="$CC -E" CXX=false AR=$B/ar NM=$B/nm RANLIB=$B/ranlib AS=$B/as LD=$B/ld \
    OBJDUMP=$B/objdump STRIP=$B/strip OBJCOPY=$B/objcopy \
    AR_FOR_TARGET=$B/ar AS_FOR_TARGET=$B/as LD_FOR_TARGET=$B/ld NM_FOR_TARGET=$B/nm \
    RANLIB_FOR_TARGET=$B/ranlib OBJDUMP_FOR_TARGET=$B/objdump STRIP_FOR_TARGET=$B/strip \
    OBJCOPY_FOR_TARGET=$B/objcopy \
    gcc_cv_libc_provides_ssp=yes gcc_cv_target_dl_iterate_phdr=yes \
    "$SRC/configure" --build=$T --host=$T --target=$T --prefix="$P" \
    --with-sysroot="$S" --with-native-system-header-dir=/usr/include \
    --with-gmp="$U" --with-mpfr="$U" --with-mpc="$U" --enable-languages=c,c++ \
    --disable-bootstrap --disable-multilib --disable-shared --disable-nls --disable-libmudflap \
    --disable-libssp --disable-libgomp --disable-libquadmath --disable-libitm --disable-lto \
    --disable-plugin --disable-sjlj-exceptions --with-as=$B/as --with-ld=$B/ld --disable-werror
make -j"${JOBS:-4}" MAKEINFO=true BOOT_CFLAGS=-O2 CFLAGS=-O2 CXXFLAGS=-O2
make install MAKEINFO=true ${DEST:+DESTDIR=$DEST}
