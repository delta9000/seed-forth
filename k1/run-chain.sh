#!/bin/sh
# The ladder under K0 -> K1: QEMU runs K0 (from k0/k0.hex0); K0 runs the seed
# route and builds K1 with tcc-boot2; K1 imports the input disk and runs
# /k1.recipe (hex0-seed -> ... -> Linux), writes results to the output disk,
# and kexecs into the Linux it built.  The host only runs QEMU.
#   k1/run-chain.sh            (disks in $K1_DISKS, default /annex/scratch/seed-forth-k1)
set -eu
cd "$(dirname "$0")/.."
D=${K1_DISKS:-/annex/scratch/seed-forth-k1}
HEX0=vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
mkdir -p build-out/k1
"$HEX0" k0/k0.hex0 build-out/k1/k0.bin
python3 k1/mkboot.py build-out/k1/boot.img
python3 k1/mkdisk.py "$D/in.img"
rm -f "$D/out.img"
truncate -s 4G "$D/out.img"
accel="-accel kvm -cpu host"
[ -w /dev/kvm ] || accel="-cpu max"
set +e
qemu-system-x86_64 $accel -m ${K1_MEM:-24G} -display none -monitor none \
    -serial file:"$D/serial.log" -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x01 \
    -kernel build-out/k1/k0.bin \
    -device loader,file=build-out/k1/boot.img,addr=0x50000000,force-raw=on \
    -drive file="$D/in.img",format=raw,if=ide,index=0 \
    -drive file="$D/out.img",format=raw,if=ide,index=1
rc=$?
echo "run-chain: qemu exit $rc (85 = the chain's Linux ran its /init)"
[ "$rc" -eq 85 ]
