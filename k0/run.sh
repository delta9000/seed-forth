#!/bin/sh
# Build K0 and run the direct seed-Forth-to-TinyCC route under it in QEMU.
# Run from the repository root.
set -e
cd "$(dirname "$0")/.."
HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}
mkdir -p build-out/k0
"$HEX0" k0/k0.hex0 build-out/k0/k0.bin
echo "k0.bin: $(stat -c %s build-out/k0/k0.bin) bytes"
python3 k0/mkfs.py build-out/k0/fs.img
accel="-accel kvm -cpu host"
[ -w /dev/kvm ] || accel="-cpu max"
set +e
"${QEMU:-qemu-system-x86_64}" $accel -m 3G -display none -monitor none \
    -serial file:build-out/k0/serial.log -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x01 \
    -kernel build-out/k0/k0.bin \
    -device loader,file=build-out/k0/fs.img,addr=0x50000000,force-raw=on
rc=$?
set -e
cat build-out/k0/serial.log
# isa-debug-exit reports (status << 1) | 1; anything even is a crash
# (a triple fault with -no-reboot exits 0). QEMU startup errors also exit 1,
# so require the guest recipe's success marker as well.
if [ $((rc % 2)) -eq 1 ]; then
    echo "k0: init status $(( rc >> 1 ))"
else
    echo "k0: crashed (qemu exit $rc)"
fi
[ "$rc" -eq 1 ]
grep -q "^direct-tcc: PASS " build-out/k0/serial.log || {
    echo "k0: missing direct TinyCC guest success marker" >&2; exit 1;
}
