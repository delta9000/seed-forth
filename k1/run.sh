#!/bin/sh
# Boot K0 -> K1 in QEMU.  Run from the repository root.
#   k1/run.sh [mkimg options] -- k1 [-i stdin] prog args...
# Default: the direct seed-Forth-to-TinyCC route, as k0/run.sh runs it.
set -e
cd "$(dirname "$0")/.."
HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}
B=build-out/k1
mkdir -p $B
"$HEX0" k0/k0.hex0 $B/k0.bin
k1/build.sh
default_route=0
if [ $# -eq 0 ]; then
    default_route=1
    set -- -- k1 -i tools/tcc-ladder-start.fth seed-forth
fi
python3 k1/mkimg.py $B/fs.img "$@"
accel="-accel kvm -cpu host"
[ -w /dev/kvm ] || accel="-cpu max"
set +e
"${QEMU:-qemu-system-x86_64}" $accel -m ${K1_MEM:-16G} -display none -monitor none \
    -serial file:$B/serial.log -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x01 \
    -kernel $B/k0.bin \
    -device loader,file=$B/fs.img,addr=0x50000000,force-raw=on
rc=$?
set -e
cat "$B/serial.log"
if [ $((rc % 2)) -eq 1 ]; then
    echo "k1: qemu status $(( rc >> 1 ))"
else
    echo "k1: crashed (qemu exit $rc)"
fi
[ "$rc" -eq 1 ]
if [ "$default_route" -eq 1 ]; then
    grep -q "^direct-tcc: PASS " "$B/serial.log" || {
        echo "k1: missing direct TinyCC guest success marker" >&2; exit 1;
    }
fi
