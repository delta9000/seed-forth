#!/bin/bash
# build-gcc10.sh CC CXX PREFIX [DESTDIR] -- gcc-10.5.0 (C, C++) for x86_64-linux-musl,
# single stage, live-bootstrap's patches, against $W/sysroot, binutils-2.41 ($W/bu2).
set -euo pipefail
W=${GCC64_W:?run via gcc64/run-gcc64.sh} DIST=${GCC64_CACHE:?} PATCHES=${GCC64_PATCHES:?}
CC=$1 CXX=$2 P=$3 DEST=${4:-}
T=x86_64-linux-musl S=$W/sysroot U=$W/sysroot/usr B=$W/bu2/bin
SRC=$W/src/gcc-10.5.0 BLD=$W/src/g10-build
rm -rf "$SRC" "$BLD"
tar -xJf "$DIST/gcc-10.5.0.tar.xz" -C "$W/src" --exclude='gcc-10.5.0/gcc/testsuite/[!s]*' \
    --exclude='gcc-10.5.0/libgo' --exclude='gcc-10.5.0/libgfortran' \
    --exclude='gcc-10.5.0/libada' --exclude='gcc-10.5.0/gnattools' \
    --exclude='gcc-10.5.0/libphobos' \
    --exclude='gcc-10.5.0/libsanitizer' \
    --exclude='gcc-10.5.0/libobjc' --exclude='gcc-10.5.0/libhsail-rt' --exclude='gcc-10.5.0/gotools'
cd "$SRC"
for p in includes libgcc-xfmode no-isolate-erroneous-paths-dereference; do
    patch -s -p1 -F0 < "$PATCHES/gcc-10.5.0/$p.patch"   # = live-bootstrap steps/gcc-10.5.0/patches
done
mkdir "$BLD"; cd "$BLD"
env CC="$CC" CXX="$CXX" CFLAGS="-O2 -std=gnu11" CXXFLAGS="-O2" LDFLAGS=-static \
    AR=$B/ar NM=$B/nm RANLIB=$B/ranlib AS=$B/as LD=$B/ld OBJDUMP=$B/objdump STRIP=$B/strip OBJCOPY=$B/objcopy \
    AR_FOR_TARGET=$B/ar AS_FOR_TARGET=$B/as LD_FOR_TARGET=$B/ld NM_FOR_TARGET=$B/nm \
    RANLIB_FOR_TARGET=$B/ranlib OBJDUMP_FOR_TARGET=$B/objdump STRIP_FOR_TARGET=$B/strip \
    OBJCOPY_FOR_TARGET=$B/objcopy READELF_FOR_TARGET=$B/readelf \
    "$SRC/configure" --build=$T --host=$T --target=$T --prefix="$P" \
    --with-sysroot="$S" --with-native-system-header-dir=/usr/include \
    --with-gmp="$U" --with-mpfr="$U" --with-mpc="$U" --enable-languages=c,c++ \
    --disable-bootstrap --disable-multilib --disable-shared --enable-static --disable-nls \
    --disable-libsanitizer --disable-libssp --disable-libgomp --disable-libquadmath --disable-libitm \
    --disable-libvtv --disable-lto --disable-plugin --disable-sjlj-exceptions --enable-threads=posix \
    --with-as=$B/as --with-ld=$B/ld --disable-werror --without-isl --without-zstd
make -j"${JOBS:-4}" MAKEINFO=true
make install MAKEINFO=true ${DEST:+DESTDIR=$DEST}
