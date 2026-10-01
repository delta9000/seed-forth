#!/bin/sh
# Boot the Linux kernel tools/chain-root.sh built, in QEMU.  Its initramfs
# /init (ladder/init.c) prints the kernel's version line and exits QEMU
# through isa-debug-exit with status 42, which QEMU reports as 85.
set -eu
cd "$(dirname "$0")/.."
K=build-out/chain-root/build-out/linux/bzImage
accel="-accel kvm -cpu host"
[ -w /dev/kvm ] || accel="-cpu max"
set +e
timeout 300 qemu-system-x86_64 $accel -m 512M -display none -monitor none \
    -serial stdio -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x01 \
    -kernel "$K"
rc=$?
if [ "$rc" -eq 85 ]; then echo "boot-linux: PASS (init ran, qemu exit 85)"; else echo "boot-linux: FAIL (qemu exit $rc)"; exit 1; fi
