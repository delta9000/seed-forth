#!/bin/sh
# Build K1 with the chain's own tcc (tcc-boot2, copied to build-out/k1/tcc).
# Run from the repository root.
set -e
B=build-out/k1
TCC=${TCC:-$B/tcc}
mkdir -p $B
$TCC ${K1_CFLAGS:--g} -nostdlib -nostdinc -static -Wl,-Ttext=200000,-section-alignment=1000 \
    -o $B/k1 k1/k1.S k1/main.c k1/mm.c k1/fs.c k1/proc.c k1/sys.c k1/linux.c k1/ata.c \
    $B/libtcc1.a
echo "k1: $(stat -c %s $B/k1) bytes"
