#!/bin/sh
# K1 without TinyCC, checked on the host.  Run from the repository root after
# ./build.sh.  About a minute; needs GNU as for the assembly comparison.
#   1. tools/k1-direct.recipe lists exactly the compiler layers seed-cc uses.
#   2. ./seed-forth < tools/k1-direct-start.fth builds build-out/k1-direct/k1
#      under strace: every execve is the seed or the runner it built.
#   3. Each C object equals seed-cc -nostdinc -c's, and k1/k1-asm.fth's
#      object equals GNU as's for k1/k1.S (k1/tests/asm-check.py).
#   4. The kernel is a static ELF at 0x200000 whose image ends below 4 MiB
#      (K1 maps only its low 4 MiB for itself).
set -eu
cd "$(dirname "$0")/../.."
K=build-out/k1-direct

expected=$(ls [0-9][0-9][0-9]-cc-*.fth | grep -v -e '^120-cc-main.fth$' -e '^140-cc-link.fth$' \
           | sed 's|^|${ROOT}/|' | tr '\n' ' ' | sed 's/ $//')
listed=$(sed -n 's|^cat ${K}/compiler.fth ${ROOT}/010-lib.fth ${ROOT}/k1/boot/k0-syscalls.fth ||p' tools/k1-direct.recipe)
[ "$listed" = "$expected" ] || {
    echo "direct-build-check: tools/k1-direct.recipe's layer list is not the sorted NNN-cc-*.fth" >&2
    echo "  expected: $expected" >&2
    echo "  listed:   $listed" >&2
    exit 1
}
echo "direct-build-check: recipe lists all $(echo "$expected" | wc -w) compiler layers"

rm -rf "$K"
if command -v strace >/dev/null; then
    strace -f -qq -e trace=execve -o build-out/k1-direct.trace ./seed-forth < tools/k1-direct-start.fth
    bad=$(grep 'execve("' build-out/k1-direct.trace | grep -v -e 'execve("./seed-forth"' \
          -e 'execve("[^"]*/seed-forth"' -e 'execve("build-out/amd64-runner"' || true)
    [ -z "$bad" ] || { echo "direct-build-check: unexpected programs ran:" >&2; echo "$bad" >&2; exit 1; }
    echo "direct-build-check: $(grep -c 'execve("' build-out/k1-direct.trace) execve calls, all the seed or the runner"
else
    ./seed-forth < tools/k1-direct-start.fth
    echo "direct-build-check: strace not found; execve audit skipped"
fi

[ -x build-out/seed-cc/seed-cc ] || ./seed-forth < tools/seed-cc-start.fth
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
for f in main mm fs proc sys linux ata; do
    build-out/seed-cc/seed-cc -nostdinc -c k1/$f.c -o "$T/$f.o"
    cmp "$K/$f.o" "$T/$f.o"
done
echo "direct-build-check: the seven C objects equal seed-cc -nostdinc -c's"
python3 k1/tests/asm-check.py

python3 - "$K/k1" <<'EOF'
import struct, sys
data = open(sys.argv[1], "rb").read()
assert data[:4] == b"\x7fELF" and data[16] == 2, "not a static ELF executable"
entry, phoff = struct.unpack_from("<QQ", data, 24)
phnum, = struct.unpack_from("<H", data, 56)
loads = [struct.unpack_from("<IIQQQQQQ", data, phoff + 56 * i) for i in range(phnum)]
loads = [p for p in loads if p[0] == 1]
low = min(p[3] for p in loads)
high = max(p[3] + p[6] for p in loads)
assert low == 0x200000, hex(low)
assert high <= 0x400000, hex(high)
print(f"direct-build-check: K1 is {len(data)} bytes, image {low:#x}-{high:#x}, entry {entry:#x}")
EOF
