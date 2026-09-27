#!/bin/bash
# mktcc.sh CC CC_LIBC OUTPREFIX SRC [extra cflags...]
#   CC        a tcc that runs now
#   CC_LIBC   musl prefix whose headers/crt/libc.a the new tcc is linked against
#   OUTPREFIX where the new tcc (bin/tcc) and its libtcc1.a (lib/tcc/) go; the
#             new tcc looks for musl in OUTPREFIX too (a copy of CC_LIBC is
#             installed there by the caller).
#   SRC       tcc-0.9.27 source tree
set -euo pipefail
CC=$1 ML=$2 P=$3 S=$4; shift 4
mkdir -p "$P/bin" "$P/lib/tcc" "$P/obj"
O=$P/obj
# libtcc1.a for the new tcc, built by CC against CC_LIBC
$CC -nostdinc -I "$ML/include" -c -o $O/libtcc1.o "$S/lib/libtcc1.c"
$CC -nostdinc -I "$ML/include" -c -o $O/va_list.o "$S/lib/va_list.c"
$CC -c -o $O/alloca86_64.o "$S/lib/alloca86_64.S"
rm -f $O/libtcc1.a; $CC -ar cr $O/libtcc1.a $O/libtcc1.o $O/va_list.o $O/alloca86_64.o
$CC -nostdinc -I "$ML/include" -c -o $O/tcc.o \
  -D BOOTSTRAP=1 -D HAVE_FLOAT=1 -D HAVE_BITFIELD=1 -D HAVE_LONG_LONG=1 -D HAVE_SETJMP=1 \
  -D TCC_TARGET_X86_64=1 -D ONE_SOURCE=1 -D 'TCC_VERSION="0.9.27"' \
  -D "CONFIG_TCCDIR=\"$P/lib/tcc\"" -D "CONFIG_TCC_CRTPREFIX=\"$P/lib\"" \
  -D "CONFIG_TCC_LIBPATHS=\"$P/lib:$P/lib/tcc\"" -D "CONFIG_TCC_SYSINCLUDEPATHS=\"$P/include\"" \
  -D "TCC_LIBGCC=\"$P/lib/libc.a\"" -D 'TCC_LIBTCC1="libtcc1.a"' \
  -D 'CONFIG_TCC_ELFINTERP="/lib/ld-musl-x86_64.so.1"' -D CONFIG_TCC_STATIC=1 -D CONFIG_USE_LIBGCC=1 \
  "$@" "$S/tcc.c"
$CC -static -nostdlib -o "$P/bin/tcc" "$ML/lib/crt1.o" "$ML/lib/crti.o" $O/tcc.o \
  "$ML/lib/libc.a" $O/libtcc1.a "$ML/lib/crtn.o"
cp $O/libtcc1.a "$P/lib/tcc/libtcc1.a"
