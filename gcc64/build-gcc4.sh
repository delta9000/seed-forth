#!/bin/bash
# build-gcc4.sh CC PREFIX NAME [DESTDIR] -- gcc-4.0.4 (C only) the way
# live-bootstrap's steps/gcc-4.0.4/pass1.sh does it (libiberty, libcpp, gcc
# configured one by one, no fixincludes), for x86_64 against $W/sysroot.
# Parser generators: host bison and $W/tools/bin/flex, unless GCC4_YACC/GCC4_LEX
# name others (the bridge from the direct route passes its Forth-built oyacc and
# flex 2.5.11; GCC4_BYACC=1 then makes gcc/system.h accept Berkeley-yacc output).
set -euo pipefail
W=${GCC64_W:?run via gcc64/run-gcc64.sh} DIST=${GCC64_CACHE:?} PATCHES=${GCC64_PATCHES:?}
CC=$1 P=$2 NAME=$3 DEST=${4:-}
T=x86_64-unknown-linux-gnu S=$W/sysroot
YACC=${GCC4_YACC:-bison} LEX=${GCC4_LEX:-$W/tools/bin/flex}
SRC=$W/src/gcc-4.0.4-work   # same path every time: the build dir ends up in the binaries
rm -rf "$SRC" "$SRC.tmp"; mkdir -p "$SRC.tmp"
tar -xf "$DIST/gcc-4.0.4-git-944765863e.tar" -C "$SRC.tmp" \
    --exclude='gcc-4.0.4/libjava' --exclude='gcc-4.0.4/gcc/testsuite' --exclude='gcc-4.0.4/libgfortran' \
    --exclude='gcc-4.0.4/libstdc++-v3' --exclude='gcc-4.0.4/libada' --exclude='gcc-4.0.4/gcc/ada' \
    --exclude='gcc-4.0.4/boehm-gc' --exclude='gcc-4.0.4/libffi' --exclude='gcc-4.0.4/gcc/java' \
    --exclude='gcc-4.0.4/gcc/fortran' --exclude='gcc-4.0.4/gcc/cp' --exclude='gcc-4.0.4/gcc/objc' \
    --exclude='gcc-4.0.4/gcc/objcp' --exclude='gcc-4.0.4/gcc/treelang' --exclude='gcc-4.0.4/libobjc'
mv "$SRC.tmp/gcc-4.0.4" "$SRC"; rmdir "$SRC.tmp"
cd "$SRC"
# live-bootstrap's edits (steps/gcc-4.0.4/pass1.sh):
sed -i 's/ix86_attribute_table\[\]/ix86_attribute_table\[10\]/' gcc/config/i386/i386.c  # tcc
sed -i 's/struct siginfo/siginfo_t/' gcc/config/i386/linux-unwind.h                      # musl
sed -i 's/YYLEX/yylex()/' gcc/c-parse.in                                                  # new bison
for p in "$PATCHES"/gcc-4.0.4/*.diff; do patch -s -p1 -F0 < "$p"; done                  # ours (collect2)
if [ "${GCC4_BYACC:-0}" = 1 ]; then   # as gcc-direct/stage-d.sh: exempt YYBYACC output from the malloc poison
    old='#if !defined(FLEX_SCANNER) && !defined(YYBISON)'
    [ "$(grep -cxF "$old" gcc/system.h)" = 1 ] || { echo "build-gcc4: unexpected gcc/system.h" >&2; exit 1; }
    sed -i 's/^#if !defined(FLEX_SCANNER) \&\& !defined(YYBISON)$/& \&\& !defined(YYBYACC)/' gcc/system.h
    grep -qxF "$old && !defined(YYBYACC)" gcc/system.h || { echo "build-gcc4: system.h edit failed" >&2; exit 1; }
fi
case $CC in *tcc) CFL="-D HAVE_ALLOCA_H" ;; *) CFL="-O2" ;; esac
mkdir build; cd build
for dir in libiberty libcpp gcc; do
    mkdir $dir
    (cd $dir && CC=$CC CPP="$CC -E" CFLAGS="$CFL" AR="$W/bu/bin/ar" RANLIB="$W/bu/bin/ranlib" \
        BISON="$YACC" FLEX="$LEX" LEX="$LEX" \
        ../../$dir/configure --prefix="$P" --build=$T --host=$T --target=$T \
        --disable-shared --disable-nls --disable-multilib --enable-languages=c \
        --with-sysroot="$S" --with-as="$W/bu/bin/as" --with-ld="$W/bu/bin/ld" --program-transform-name=)
done
cd ..
case $CC in *tcc) sed -i 's/C_alloca/alloca/g' libiberty/alloca.c include/libiberty.h ;; esac  # tcc
ln -s . build/build-$T
mkdir -p build/gcc/include
ln -s ../../../gcc/gsyslimits.h build/gcc/include/syslimits.h
sed -i 's/^STMP_FIXINC = stmp-fixinc/STMP_FIXINC =/' build/gcc/Makefile               # no fixincludes
make -j1 -C build/gcc gengtype-yacc.c BISON="$YACC"
for dir in libiberty libcpp gcc; do
    make -j"${JOBS:-4}" -C build/$dir CFLAGS="$CFL" LIBGCC2_INCLUDES=-I"$S/usr/include" BISON="$YACC" \
        FLEX="$LEX" MAKEINFO=true
done
I=${DEST:+$DEST}$P
mkdir -p "$I/lib/gcc/$T/4.0.4/install-tools/include"
make -C build/gcc install MAKEINFO=true ${DEST:+DESTDIR=$DEST}
rm -f "$I/lib/gcc/$T/4.0.4/include/syslimits.h"
cp gcc/gsyslimits.h "$I/lib/gcc/$T/4.0.4/include/syslimits.h"
