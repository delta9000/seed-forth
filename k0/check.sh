#!/bin/sh
# k0.hex0 is what gets built; k0.asm is the same program as NASM source.
# Prove they agree: k0.hex0 is exactly what asm2hex0.py writes from
# k0.asm, and hex0-seed's k0.bin is byte-identical to nasm's.
set -e
HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
python3 k0/asm2hex0.py k0/k0.asm "$t/k0.hex0"
cmp k0/k0.hex0 "$t/k0.hex0" || { echo "k0.hex0 is stale: rerun asm2hex0.py" >&2; exit 1; }
nasm -f bin -o "$t/nasm.bin" k0/k0.asm
"$HEX0" k0/k0.hex0 "$t/hex0.bin"
cmp "$t/nasm.bin" "$t/hex0.bin"
echo "k0: k0.hex0 matches k0.asm ($(wc -c < "$t/hex0.bin") bytes)"
