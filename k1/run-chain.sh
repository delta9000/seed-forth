#!/bin/sh
# The ladder under K0 -> K1: QEMU runs K0 (from k0/k0.hex0); K0 runs the seed
# route and builds K1 with tcc-boot2; K1 imports the input disk and runs
# /k1.recipe (hex0-seed -> ... -> Linux), writes results to the output disk,
# and kexecs into the Linux it built. Host Python copies raw pinned inputs
# into disk images; after boot unpacking, patching and compilation are seed-derived.
#   k1/run-chain.sh            (disks in $K1_DISKS, default /annex/scratch/seed-forth-k1)
#   k1/run-chain.sh --seed-smoke  (K0 -> K1 -> direct TinyCC fixed point, 3 GiB)
# Optional: JOBS=1 passes into guest make; K1_RAM_FILE names a new build-out
# file for shared, non-preallocated RAM backing (K1_RAM_RESERVE defaults8G).
set -eu
cd "$(dirname "$0")/.."
[ "$#" -le 1 ] || { echo "usage: $0 [--seed-smoke]" >&2; exit 2; }
mode=${1:-}
if [ "$mode" = --seed-smoke ]; then
    D=${K1_DISKS:-build-out/k1-smoke}
    memory=${K1_MEM:-3G}
    expected=1
else
    [ -z "$mode" ] || { echo "usage: $0 [--seed-smoke]" >&2; exit 2; }
    D=${K1_DISKS:-/annex/scratch/seed-forth-k1}
    memory=${K1_MEM:-24G}
    expected=85
fi
HEX0=vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
mkdir -p build-out/k1 "$D"
"$HEX0" k0/k0.hex0 build-out/k1/k0.bin
python3 k1/mkboot.py build-out/k1/boot.img
set -- "$D/in.img"
[ -z "$mode" ] || set -- "$@" "$mode"
[ -z "${JOBS:-}" ] || set -- "$@" --jobs "$JOBS"
python3 k1/mkdisk.py "$@"
rm -f "$D/out.img"
truncate -s 4G "$D/out.img"
accel="-accel kvm -cpu host"
[ -w /dev/kvm ] || accel="-cpu max"
set --
if [ -n "${K1_RAM_FILE:-}" ]; then
    ram_file=$(python3 k1/mkram.py "$K1_RAM_FILE" "$memory" --reserve "${K1_RAM_RESERVE:-8G}")
    echo "run-chain: shared sparse RAM backing: $ram_file ($memory; reserve ${K1_RAM_RESERVE:-8G})"
    set -- -object "memory-backend-file,id=k1ram,size=$memory,mem-path=$ram_file,share=on,prealloc=off" \
           -machine memory-backend=k1ram
fi
set +e
"${QEMU:-qemu-system-x86_64}" "$@" $accel -m "$memory" -display none -monitor none \
    -serial file:"$D/serial.log" -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x01 \
    -kernel build-out/k1/k0.bin \
    -device loader,file=build-out/k1/boot.img,addr=0x50000000,force-raw=on \
    -drive file="$D/in.img",format=raw,if=ide,index=0 \
    -drive file="$D/out.img",format=raw,if=ide,index=1
rc=$?
set -e
echo "run-chain: qemu exit $rc (expected $expected)"
[ "$rc" -eq "$expected" ]
if [ "$mode" = --seed-smoke ]; then
    grep -q "^k1: PASS (K0-built K1 rebuilt the direct TinyCC fixed point from sources)" "$D/serial.log" || {
        echo "run-chain: missing K1 guest success marker" >&2; exit 1;
    }
else
    for marker in 'finish: K1 hands the machine to the Linux kernel it built' \
                  'init: hello from a Linux kernel built from hex0 and seed-forth' \
                  'init: Linux version 7.2.8'; do
        grep -Fq "$marker" "$D/serial.log" || {
            echo "run-chain: missing full Linux guest marker: $marker" >&2; exit 1;
        }
    done
fi
