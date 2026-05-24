#!/usr/bin/env bash
# Build GNU Mes (Scheme interpreter + MesCC) end-to-end via our chain:
#   forth-cc compiles M2-Planet  ->  forth-asm assembles M2-Planet
#   forth-asm-built M2-Planet compiles Mes .c sources  ->  mes.M1
#   forth-asm assembles mes.M1 + crt1.M1 + libc + ELF prefix  ->  mes-m2
# Compares byte-for-byte against mescc-tools' M1+hex2 on the same inputs,
# then smoke-tests the binary on a tiny Scheme program.
#
# Skips blood-elf and M2-Planet --debug to keep the chain free of debug-only
# tooling that adds no functional content.  The full kaem.run pipeline can
# be reconstructed on top of this base if symbol tables are desired.

set -euo pipefail
cd "$(dirname "$0")/../.."

MESCC_DIR=vendor/mescc-tools
M2LIBC=vendor/M2-Planet/M2libc/amd64
MES_SRC=vendor/mes
BUILDROOT=${BUILDROOT:-/tmp/seed-bootstrap}
M2_BIN=$BUILDROOT/m2-via-forth-asm
MES_BUILD=$BUILDROOT/mes
MES_CPU=x86_64

fail() { printf 'mes/mes-check: FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'mes/mes-check: %s\n' "$1"; }

[ -d "$MES_SRC" ] && [ -f "$MES_SRC/kaem.run" ] || \
    fail "vendor/mes not populated (git submodule update --init vendor/mes)"

[ -x seed-forth ] || ./build.sh >/dev/null
[ -x seed-forth ] || fail "seed-forth build failed"

if [ ! -x "$M2_BIN" ]; then
    pass "m2-via-forth-asm missing — running tests/asm/m2planet-check.sh..."
    tests/asm/m2planet-check.sh >/dev/null
fi
[ -x "$M2_BIN" ] || fail "$M2_BIN not produced"

if [ ! -x "$MESCC_DIR/bin/M1" ] || [ ! -x "$MESCC_DIR/bin/hex2" ]; then
    (cd "$MESCC_DIR" && make >/dev/null 2>&1) || fail "make mescc-tools failed"
fi

mkdir -p "$MES_BUILD/m2" "$MES_BUILD/bin"

# --- Mes ships config.h and arch headers as configure outputs.  We don't run
# configure (it requires hex2/M1/blood-elf on PATH); generate the minimum
# inputs Mes's headers need to compile under M2-Planet. ---
if [ ! -f "$MES_SRC/include/mes/config.h" ]; then
    mkdir -p "$MES_SRC/include/mes" "$MES_SRC/include/arch"
    cat > "$MES_SRC/include/mes/config.h" <<EOF
#undef SYSTEM_LIBC
#define MES_VERSION "0.27.1"
EOF
    cp "$MES_SRC/include/linux/$MES_CPU/kernel-stat.h" "$MES_SRC/include/arch/"
    cp "$MES_SRC/include/linux/$MES_CPU/signal.h"      "$MES_SRC/include/arch/"
    cp "$MES_SRC/include/linux/$MES_CPU/syscall.h"     "$MES_SRC/include/arch/"
fi

# --- Extract the M2-Planet section's -f file list from kaem.run. ---
mapfile -t M2_FILES < <(
  awk '
    /^M2-Planet/ { in_m2=1; next }
    /^blood-elf/ || /^M1[[:space:]]/ || /^hex2/ || /^echo/ || /^[A-Za-z]/ { in_m2=0 }
    in_m2 && /^[[:space:]]+-f / { print }
  ' "$MES_SRC/kaem.run" |
  sed -E 's|^[[:space:]]+-f \$\{srcdest\}||; s|\s*\\\s*$||; s|\$\{mes_cpu\}|'"$MES_CPU"'|g; s|\$\{cc_cpu\}|'"$MES_CPU"'|g'
)
[ "${#M2_FILES[@]}" -gt 0 ] || fail "no M2-Planet files found in kaem.run"

# --- Stage 1: M2-Planet (forth-asm-built) -> mes.M1 ---
pass "stage 1: M2-Planet compiling ${#M2_FILES[@]} mes sources..."
M2_ARGS=( --architecture amd64 -D __${MES_CPU}__=1 -D __linux__=1 )
for f in "${M2_FILES[@]}"; do M2_ARGS+=( -f "$MES_SRC/$f" ); done
M2_ARGS+=( -o "$MES_BUILD/m2/mes.M1" )
"$M2_BIN" "${M2_ARGS[@]}" || fail "M2-Planet compilation of Mes failed"
pass "  mes.M1: $(wc -c < "$MES_BUILD/m2/mes.M1") bytes"

# --- Reference: mescc-tools M1+hex2 on the same inputs ---
# Use M2-Planet's non-debug ELF-amd64.hex2 (Mes's ELF-x86_64.hex2 references
# section-header labels that only blood-elf would resolve; we don't run it).
pass "stage 2a: building reference via mescc-tools M1 + hex2..."
"$MESCC_DIR/bin/M1" --architecture amd64 --little-endian \
    -f "$MES_SRC/lib/m2/$MES_CPU/${MES_CPU}_defs.M1" \
    -f "$MES_SRC/lib/$MES_CPU-mes/$MES_CPU.M1" \
    -f "$MES_SRC/lib/linux/$MES_CPU-mes-m2/crt1.M1" \
    -f "$MES_BUILD/m2/mes.M1" \
    -o "$MES_BUILD/m2/mes-ref.hex2" \
    || fail "reference M1 failed"
"$MESCC_DIR/bin/hex2" --architecture amd64 --little-endian \
    --base-address 0x1000000 \
    -f "$M2LIBC/ELF-amd64.hex2" \
    -f "$MES_BUILD/m2/mes-ref.hex2" \
    -o "$MES_BUILD/bin/mes-m2-ref" \
    || fail "reference hex2 failed"
chmod +x "$MES_BUILD/bin/mes-m2-ref"
ref_bytes=$(wc -c < "$MES_BUILD/bin/mes-m2-ref")
pass "  mes-m2-ref: $ref_bytes bytes"

# --- Stage 2b: forth-asm produces the same binary ---
pass "stage 2b: forth-asm linking mes (base=0x1000000)..."
strip_forth() { sed -e 's/\\.*$//' -e 's/([^)]*)//g' | grep -v '^[[:space:]]*$'; }
INPUT=$MES_BUILD/forth-asm-mes-input.txt
{ cat 010-lib.fth 130-asm.fth | strip_forth ;
  printf '[lit] 16777216 asm-base !\nasm-main\n' ;
  cat "$M2LIBC/ELF-amd64.hex2" ;
  cat "$MES_SRC/lib/m2/$MES_CPU/${MES_CPU}_defs.M1" ;
  cat "$MES_SRC/lib/$MES_CPU-mes/$MES_CPU.M1" ;
  cat "$MES_SRC/lib/linux/$MES_CPU-mes-m2/crt1.M1" ;
  cat "$MES_BUILD/m2/mes.M1" ;
} > "$INPUT"

rm -f /tmp/asm-out
./seed-forth < "$INPUT" || fail "seed-forth exited non-zero"
[ -f /tmp/asm-out ] || fail "/tmp/asm-out not produced"
cp /tmp/asm-out "$MES_BUILD/bin/mes-m2"
chmod +x "$MES_BUILD/bin/mes-m2"

if cmp -s "$MES_BUILD/bin/mes-m2-ref" "$MES_BUILD/bin/mes-m2"; then
    pass "  byte-identical to mescc-tools reference ($(wc -c < "$MES_BUILD/bin/mes-m2") bytes)"
else
    cmp "$MES_BUILD/bin/mes-m2-ref" "$MES_BUILD/bin/mes-m2" || true
    fail "forth-asm mes output differs from reference"
fi

# --- Stage 3: smoke-test the binary on a tiny Scheme program ---
pass "stage 3: running mes-m2 on a Scheme expression..."
OUTPUT=$(cd "$MES_SRC" && \
    MES_PREFIX="$PWD/mes" MES_BOOT=boot-5.scm \
    "$MES_BUILD/bin/mes-m2" \
    -c "(display 'mes-via-forth-asm)(newline)(display (* 6 7))(newline)" 2>&1)
echo "$OUTPUT" | grep -q "mes-via-forth-asm" || fail "mes-m2 did not print expected symbol"
echo "$OUTPUT" | grep -q "^42$"               || fail "mes-m2 did not evaluate (* 6 7)"
pass "  mes-m2 runs Scheme correctly:"
echo "$OUTPUT" | sed 's/^/    /'

pass "PASS"
