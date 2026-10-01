# ladder/stage12.sh: Linux, built inside the chain root by the chain's
# gcc-10.5.0 and binutils-2.41 (stage 11), with libelf for objtool.
# Output: /build-out/linux/bzImage, with an initramfs holding ladder/init.c.
set -eu
export PATH=/build-out/g64/g10/bin:/build-out/g64/bu2/bin:/usr/bin:/bin
export HOME=/ SHELL=/bin/sh LC_ALL=C TZ=UTC0 TAR_OPTIONS=--no-same-owner
export lt_cv_sys_max_cmd_len=1572864
unset CC LD AR RANLIB CFLAGS CC_FOR_BUILD BUILD_CC
D=/build-out/distfiles
S=/build-out/s12
P=/build-out/s12/host                   # zlib and libelf, for objtool
LOG=/build-out/s12-logs
O=/build-out/linux
mkdir -p "$S" "$P" "$LOG" "$O"
say() { echo "stage12: $*"; }
fail() {
    echo "stage12: FAIL: $*" >&2
    # The log named in the message is inside the build: show its end.
    log=$(echo "$*" | sed -n 's/.*(see \(.*\))$/\1/p')
    [ -n "$log" ] && [ -f "$log" ] && {
        echo "=== errors in $log" >&2; grep -n -E 'error|Error [0-9]|No such|not found' "$log" | head -n 30 >&2
        echo "=== tail of $log" >&2; tail -n 30 "$log" >&2; }
    exit 1
}
unpack() {
    echo "$3  $D/$2" | sha256sum -c --quiet || fail "sha256 $2"
    rm -rf "$S/$1" "$S/$1.tmp"
    mkdir -p "$S/$1.tmp"
    tar -xf "$D/$2" -C "$S/$1.tmp"
    mv "$S/$1.tmp"/* "$S/$1"
    rmdir "$S/$1.tmp"
    for pt in /patches/ladder/$1/*.diff; do
        [ -e "$pt" ] || continue
        patch -d "$S/$1" -p1 -F0 < "$pt" > /dev/null || fail "patch $pt"
    done
}
gcc --version | head -1
ld --version | head -1

if [ ! -e "$LOG/zlib.done" ]; then
    unpack zlib-1.3.1 zlib-1.3.1.tar.gz 9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
    ( cd "$S/zlib-1.3.1" && CC=gcc ./configure --prefix=$P --static && make -j16 && make install ) \
        > "$LOG/zlib.log" 2>&1 || fail "zlib (see $LOG/zlib.log)"
    touch "$LOG/zlib.done"; say zlib-1.3.1
fi

# elfutils: only libelf/ (objtool needs libelf.a, gelf.h and libelf.h).  Its
# lib/ and tools need argp, fts and obstack, which musl lacks; libelf does not,
# so configure is told they need no library.
if [ ! -e "$LOG/elfutils.done" ]; then
    unpack elfutils-0.192 elfutils-0.192.tar.bz2 616099beae24aba11f9b63d86ca6cc8d566d968b802391334c91df54eab416b4
    ( cd "$S/elfutils-0.192" &&
      ac_cv_tls=yes ac_cv_search_argp_parse="none required" ac_cv_search_fts_close="none required" \
      ac_cv_search__obstack_free="none required" ac_cv_search_fts_open="none required" CC=gcc CFLAGS="-O2 -I$P/include" LDFLAGS="-L$P/lib" ./configure --prefix=$P \
        --disable-debuginfod --disable-libdebuginfod --disable-nls --disable-shared \
        --without-bzlib --without-lzma --without-zstd --disable-demangler &&
      make -C libelf -j16 libelf.a &&
      make -C lib -j16 xasprintf.o xstrdup.o xstrndup.o xmalloc.o next_prime.o \
          crc32.o crc32_file.o eu-search.o error.o &&       # libeu, less its argp parts
      ar r libelf/libelf.a lib/xasprintf.o lib/xstrdup.o lib/xstrndup.o lib/xmalloc.o \
          lib/next_prime.o lib/crc32.o lib/crc32_file.o lib/eu-search.o lib/error.o &&
      mkdir -p $P/lib $P/include &&
      cp libelf/libelf.a $P/lib/ &&
      cp libelf/libelf.h libelf/gelf.h libelf/nlist.h $P/include/ &&
      mkdir -p $P/include/elfutils && cp libelf/elf-knowledge.h version.h $P/include/elfutils/ 2>/dev/null; true
    ) > "$LOG/elfutils.log" 2>&1 || fail "elfutils (see $LOG/elfutils.log)"
    [ -e $P/lib/libelf.a ] || fail "elfutils: no libelf.a (see $LOG/elfutils.log)"
    touch "$LOG/elfutils.done"; say elfutils-0.192 libelf
fi

# The initramfs: /init from ladder/init.c, static against gcc-10's musl.
gcc -static -O2 -o $O/init /ladder/init.c || fail "init"
printf 'dir /dev 755 0 0\nnod /dev/console 600 0 0 c 5 1\ndir /proc 755 0 0\nfile /init %s 755 0 0\n' \
    $O/init > $O/initramfs.list

if [ ! -e "$LOG/linux.done" ]; then
    unpack linux-7.2.8 linux-7.2.8.tar.xz 12e8d5a973d1ad7c5a5c69882e4022b131ed715db7003fdcd760ddf8c3e51941
    cd "$S/linux-7.2.8"
    # Host programs (objtool, vdso2c ...) find libelf/zlib and the UAPI headers
    # here; -idirafter keeps the kernel's own tools/include first, and -lz must
    # follow objtool's -lelf (there is no pkg-config to say so).
    export HOSTCFLAGS="-idirafter $P/include" HOSTLDFLAGS="-L$P/lib -lz"
    K="make KBUILD_BUILD_TIMESTAMP=@0 KBUILD_BUILD_USER=chain KBUILD_BUILD_HOST=chain-root"
    {
        $K tinyconfig &&
        ./scripts/config -e 64BIT -e PRINTK -e TTY -e SERIAL_8250 -e SERIAL_8250_CONSOLE \
            -e BINFMT_ELF -e BINFMT_SCRIPT -e BLK_DEV_INITRD -e PROC_FS -e SYSFS \
            -e EARLY_PRINTK -e RD_GZIP -e KERNEL_GZIP -d KERNEL_XZ \
            -e X86_IOPL_IOPERM \
            -e CMDLINE_BOOL --set-str CMDLINE "console=ttyS0 panic=-1" \
            --set-str INITRAMFS_SOURCE "$O/initramfs.list" &&
        $K olddefconfig &&
        $K headers &&                     # asm/ and linux/ for host tools; headers_install
        cp -r usr/include/. $P/include/ &&  # would copy them with rsync
        $K -j16 bzImage
    } > "$LOG/linux.log" 2>&1 || fail "linux (see $LOG/linux.log)"
    cp arch/x86/boot/bzImage $O/bzImage
    cp .config $O/config
    touch "$LOG/linux.done"
fi
say "linux-7.2.8: $O/bzImage ($(wc -c < $O/bzImage) bytes) $(sha256sum < $O/bzImage | cut -c1-16)"
