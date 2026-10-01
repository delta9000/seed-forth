#!/bin/sh
# Boot K0 -> K1 in QEMU.  Run from the repository root.
#   k1/run.sh [mkimg options] -- k1 [-i stdin] prog args...
# Default: the seed-only amd64 route, as k0/run.sh runs it.
set -e
HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}
B=build-out/k1
mkdir -p $B
"$HEX0" k0/k0.hex0 $B/k0.bin
k1/build.sh
if [ $# -eq 0 ]; then
    set -- -- k1 -i tools/amd64-start.fth seed-forth
fi
python3 k1/mkimg.py $B/fs.img "$@"
accel="-accel kvm -cpu host"
[ -w /dev/kvm ] || accel="-cpu max"
set +e
qemu-system-x86_64 $accel -m ${K1_MEM:-16G} -display none -monitor none \
    -serial stdio -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x01 \
    -kernel $B/k0.bin \
    -device loader,file=$B/fs.img,addr=0x50000000,force-raw=on
rc=$?
if [ $((rc % 2)) -eq 1 ]; then
    echo "k1: qemu status $(( rc >> 1 ))"
else
    echo "k1: crashed (qemu exit $rc)"
fi
[ "$rc" -eq 1 ]
