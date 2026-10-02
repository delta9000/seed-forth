#!/bin/sh
# Build K1 with the direct route's generated tcc-boot2.
# Run tools/tcc-ladder-start.fth through seed-forth first.
# Run from the repository root.
set -e
B=build-out/k1
TCC=${TCC:-build-out/pnut-amd64/kit/build/tcc-boot2}
LIBTCC1=${LIBTCC1:-build-out/pnut-amd64/kit/build/boot2-lib/tcc/libtcc1.a}
mkdir -p $B
$TCC ${K1_CFLAGS:--g} -nostdlib -nostdinc -static -Wl,-Ttext=200000,-section-alignment=1000 \
    -o $B/k1 k1/k1.S k1/main.c k1/mm.c k1/fs.c k1/proc.c k1/sys.c k1/linux.c k1/ata.c \
    "$LIBTCC1"
echo "k1: $(stat -c %s $B/k1) bytes"
