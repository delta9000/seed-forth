#!/usr/bin/env bash
# Reproduce the seed-forth -> M2-Planet bootstrap chain end-to-end.
#
# Stages run for each architecture in $ARCHES (default: x86 amd64):
#   v1   = seed-forth-compiled M2-Planet (always 64-bit ELF; arch-of-OUTPUT
#          is selected by --architecture).  Built once and reused.
#   v2_$ARCH = M1+hex2 from v1's self-compile at $ARCH (32- or 64-bit ELF
#          depending on $ARCH).  No GCC in this binary's provenance.
#   v3_$ARCH = M1+hex2 from v2_$ARCH's self-compile.  Fixed-point check.
#
# Per-arch sub-stages:
#   A. v1 self-compiles M2-Planet for $ARCH; compare to gcc-built reference.
#   B. M1 + hex2 assemble that .M1 -> cc-out-v2-$ARCH (target-arch ELF).
#   C. v2 sanity: tiny.c compiles to the same .M1 as v1 does for $ARCH.
#   D. v2 self-compiles M2-Planet.  At 32-bit and at 64-bit the resulting
#      .M1 differs slightly from v1's due to M2-Planet's own host-arch
#      sensitivity in write_sub_immediate / Architecture & ARCH_FAMILY_X86;
#      this is recorded but not a hard failure.
#   E. M1 + hex2 assemble v2's self-compile -> cc-out-v3-$ARCH.
#   F. v3 self-compiles M2-Planet; must be byte-identical to v2's
#      self-compile (fixed-point closure at $ARCH).
#   G. End-to-end smoke: v3 compiles hello.c, M1+hex2 link, run, check
#      stdout and exit code.
#
# Stage 9 (after all arches): every M2-Planet test source produces
# byte-identical output from v1 vs the gcc reference (x86 only, the
# canonical reproducibility target).
#
# Env overrides:
#   M2_PLANET     - path to M2-Planet checkout    (default vendor/M2-Planet)
#   MESCC_TOOLS   - path to mescc-tools checkout  (default vendor/mescc-tools)
#   BUILDROOT     - where artifacts land          (default /tmp/seed-bootstrap)
#   ARCHES        - space-separated arches        (default "x86 amd64")
#
# Exit code is the failing stage number (1..) on failure, 0 on full pass.

set -euo pipefail
cd "$(dirname "$0")/../.."

M2_PLANET=${M2_PLANET:-vendor/M2-Planet}
MESCC_TOOLS=${MESCC_TOOLS:-vendor/mescc-tools}
BUILDROOT=${BUILDROOT:-/tmp/seed-bootstrap}
ARCHES=${ARCHES:-"x86 amd64"}

mkdir -p "$BUILDROOT"

# Resolve to absolute paths — the M1/hex2 build cd's into MESCC_TOOLS, and the
# per-arch chain cd's into M2_PLANET, so relative paths to the other tree
# stop resolving after the cd.
M2_PLANET=$(cd "$M2_PLANET" && pwd)
MESCC_TOOLS=$(cd "$MESCC_TOOLS" && pwd)
BUILDROOT=$(cd "$BUILDROOT" && pwd)

step() { printf '\n=== STAGE %s: %s ===\n' "$1" "$2"; }
fail() { printf 'FAIL (stage %s): %s\n' "$1" "$2" >&2; exit "$1"; }

# Architecture lookup tables.
arch_libdir() {
    case "$1" in
        x86)   echo M2libc/x86   ;;
        amd64) echo M2libc/amd64 ;;
        *)     fail 0 "unsupported ARCH '$1' (only x86 and amd64 wired up)" ;;
    esac
}
arch_defs() {
    case "$1" in
        x86)   echo M2libc/x86/x86_defs.M1     ;;
        amd64) echo M2libc/amd64/amd64_defs.M1 ;;
    esac
}
arch_elf_hex2() {
    case "$1" in
        x86)   echo M2libc/x86/ELF-x86.hex2     ;;
        amd64) echo M2libc/amd64/ELF-amd64.hex2 ;;
    esac
}
arch_libc_full() {
    case "$1" in
        x86)   echo M2libc/x86/libc-full.M1     ;;
        amd64) echo M2libc/amd64/libc-full.M1   ;;
    esac
}
arch_base() {
    case "$1" in
        x86)   echo 0x08048000 ;;
        amd64) echo 0x00600000 ;;
    esac
}

# ---------------------------------------------------------------------------
step 0 "prereqs"
# ---------------------------------------------------------------------------
[ -f "$M2_PLANET/cc.c" ] || fail 0 "M2_PLANET=$M2_PLANET is not initialized (run git submodule update --init --recursive)"
[ -f "$M2_PLANET/M2libc/bootstrappable.c" ] || fail 0 "M2_PLANET/M2libc is not initialized (run git submodule update --init --recursive)"
[ -f "$MESCC_TOOLS/M1-macro.c" ] || fail 0 "MESCC_TOOLS=$MESCC_TOOLS is not initialized (run git submodule update --init --recursive)"
command -v gcc >/dev/null || fail 0 "gcc not on PATH (needed for reference + M1/hex2)"

# seed-forth
[ -x seed-forth ] || ./build.sh >/dev/null
[ -x seed-forth ] || fail 0 "seed-forth did not build"

# gcc-built reference M2-Planet, for byte-identical comparisons
if [ ! -x "$BUILDROOT/m2-ref" ]; then
    (cd "$M2_PLANET" && make >/dev/null 2>&1) || fail 0 "make M2-Planet (reference) failed"
    cp "$M2_PLANET/bin/M2-Planet" "$BUILDROOT/m2-ref"
fi
[ -x "$BUILDROOT/m2-ref" ] || fail 0 "$BUILDROOT/m2-ref not produced"

# M1, hex2 — needed to assemble v1's M2-Planet self-compile into an ELF.
# Headers in $M2_PLANET resolve M1-macro.c's `#include "M2libc/..."`.
if [ ! -x "$BUILDROOT/M1" ]; then
    (cd "$MESCC_TOOLS" && gcc -D_GNU_SOURCE -std=c99 -fno-common \
        -I "$M2_PLANET" \
        M1-macro.c stringify.c "$M2_PLANET/M2libc/bootstrappable.c" \
        -o "$BUILDROOT/M1") || fail 0 "gcc M1 build failed"
fi
if [ ! -x "$BUILDROOT/hex2" ]; then
    (cd "$MESCC_TOOLS" && gcc -D_GNU_SOURCE -std=c99 -fno-common \
        -I "$M2_PLANET" \
        hex2.c hex2_linker.c hex2_word.c "$M2_PLANET/M2libc/bootstrappable.c" \
        -o "$BUILDROOT/hex2") || fail 0 "gcc hex2 build failed"
fi
[ -x "$BUILDROOT/M1"   ] || fail 0 "M1 not built"
[ -x "$BUILDROOT/hex2" ] || fail 0 "hex2 not built"
echo "prereqs OK: seed-forth, m2-ref, M1, hex2"

M1=$BUILDROOT/M1
HEX2=$BUILDROOT/hex2
M2REF=$BUILDROOT/m2-ref

# ---------------------------------------------------------------------------
step 1 "build cc-out-v1 (seed-forth compiles M2-Planet monolith)"
# ---------------------------------------------------------------------------
rm -f /tmp/cc-out
./tests/cc/build-m2planet-monolith.sh >/dev/null || fail 1 "monolith build failed"
[ -x /tmp/cc-out ] || fail 1 "/tmp/cc-out not produced"
cp /tmp/cc-out "$BUILDROOT/cc-out-v1"
v1_size=$(wc -c < "$BUILDROOT/cc-out-v1")
echo "cc-out-v1: $v1_size bytes, $(file -b "$BUILDROOT/cc-out-v1")"

# The shared source list for M2-Planet self-compile.
m2_srcs=(M2libc/bootstrappable.c cc_reader.c cc_strings.c cc_types.c
         cc_emit.c cc_core.c cc_macro.c cc.c cc.h cc_globals.c gcc_req.h)
m2_args=()
for s in "${m2_srcs[@]}"; do m2_args+=( -f "$s" ); done

# ---------------------------------------------------------------------------
# Per-arch reproduction: one big function so 32-bit and 64-bit share code.
# Sub-stage labels are A..G to distinguish from top-level numbered stages.
# Stage IDs in fail() are encoded as 100*${arch_num} + sub-stage so a
# failure pinpoints both the arch and the step (x86 -> 100s, amd64 -> 200s).
# ---------------------------------------------------------------------------
run_arch_chain() {
    local ARCH=$1
    local SID=$2          # stage ID prefix, e.g. 100 or 200
    local LIBDIR DEFS ELF LIBC BASE
    LIBDIR=$(arch_libdir   "$ARCH")
    DEFS=$(arch_defs       "$ARCH")
    ELF=$(arch_elf_hex2    "$ARCH")
    LIBC=$(arch_libc_full  "$ARCH")
    BASE=$(arch_base       "$ARCH")

    printf '\n--- arch: %s (base %s) ---\n' "$ARCH" "$BASE"

    # --- A: v1 self-compiles for $ARCH; compare to gcc reference -----------
    (cd "$M2_PLANET" && "$BUILDROOT/cc-out-v1" --architecture "$ARCH" --expand-includes \
        "${m2_args[@]}" -o "$BUILDROOT/self-v1-$ARCH.M1") \
        || fail $((SID+1)) "v1 self-compile ($ARCH) failed"
    (cd "$M2_PLANET" && "$M2REF" --architecture "$ARCH" --expand-includes \
        "${m2_args[@]}" -o "$BUILDROOT/self-ref-$ARCH.M1") \
        || fail $((SID+1)) "reference self-compile ($ARCH) failed"
    cmp "$BUILDROOT/self-v1-$ARCH.M1" "$BUILDROOT/self-ref-$ARCH.M1" \
        || fail $((SID+1)) "v1 ≠ reference at $ARCH"
    echo "A: self-v1-$ARCH.M1 == self-ref-$ARCH.M1 ($(wc -c < "$BUILDROOT/self-v1-$ARCH.M1") bytes)"

    # --- B: M1 + hex2 assemble v1's self-compile -> cc-out-v2-$ARCH --------
    (cd "$M2_PLANET" && "$M1" -f "$DEFS" -f "$LIBC" \
        -f "$BUILDROOT/self-v1-$ARCH.M1" \
        --little-endian --architecture "$ARCH" \
        -o "$BUILDROOT/self-v1-$ARCH.hex2") \
        || fail $((SID+2)) "M1 assemble ($ARCH) failed"
    (cd "$M2_PLANET" && "$HEX2" -f "$ELF" -f "$BUILDROOT/self-v1-$ARCH.hex2" \
        --little-endian --architecture "$ARCH" --base-address "$BASE" \
        -o "$BUILDROOT/cc-out-v2-$ARCH") \
        || fail $((SID+2)) "hex2 link ($ARCH) failed"
    chmod +x "$BUILDROOT/cc-out-v2-$ARCH"
    echo "B: cc-out-v2-$ARCH ($(wc -c < "$BUILDROOT/cc-out-v2-$ARCH") bytes, $(file -b "$BUILDROOT/cc-out-v2-$ARCH" | cut -d, -f1))"

    # --- C: v2 sanity on tiny.c ------------------------------------------
    "$BUILDROOT/cc-out-v1"      --architecture "$ARCH" -f "$BUILDROOT/tiny.c" -o "$BUILDROOT/tiny-v1-$ARCH.M1" \
        || fail $((SID+3)) "v1 tiny.c at $ARCH"
    "$BUILDROOT/cc-out-v2-$ARCH" --architecture "$ARCH" -f "$BUILDROOT/tiny.c" -o "$BUILDROOT/tiny-v2-$ARCH.M1" \
        || fail $((SID+3)) "v2 tiny.c at $ARCH"
    cmp "$BUILDROOT/tiny-v1-$ARCH.M1" "$BUILDROOT/tiny-v2-$ARCH.M1" \
        || fail $((SID+3)) "tiny.c output mismatch at $ARCH"
    echo "C: tiny.c v1==v2 ($(wc -c < "$BUILDROOT/tiny-v1-$ARCH.M1") bytes)"

    # --- D: v2 self-compile (host-arch nudge expected) -------------------
    (cd "$M2_PLANET" && "$BUILDROOT/cc-out-v2-$ARCH" --architecture "$ARCH" --expand-includes \
        "${m2_args[@]}" -o "$BUILDROOT/self-v2-$ARCH.M1") \
        || fail $((SID+4)) "v2 self-compile ($ARCH) failed"
    local s1 s2
    s1=$(wc -c < "$BUILDROOT/self-v1-$ARCH.M1")
    s2=$(wc -c < "$BUILDROOT/self-v2-$ARCH.M1")
    if cmp -s "$BUILDROOT/self-v1-$ARCH.M1" "$BUILDROOT/self-v2-$ARCH.M1"; then
        echo "D: self-v1-$ARCH == self-v2-$ARCH ($s2 bytes) — no host-arch nudge"
    else
        local delta
        delta=$(diff "$BUILDROOT/self-v1-$ARCH.M1" "$BUILDROOT/self-v2-$ARCH.M1" | wc -l || true)
        echo "D: self-v1-$ARCH != self-v2-$ARCH ($s1 vs $s2 bytes, diff lines: $delta) — M2-Planet host-arch nudge"
    fi

    # --- E: assemble v2 self-compile -> cc-out-v3-$ARCH -------------------
    (cd "$M2_PLANET" && "$M1" -f "$DEFS" -f "$LIBC" \
        -f "$BUILDROOT/self-v2-$ARCH.M1" \
        --little-endian --architecture "$ARCH" \
        -o "$BUILDROOT/self-v2-$ARCH.hex2") \
        || fail $((SID+5)) "M1 assemble v2 ($ARCH) failed"
    (cd "$M2_PLANET" && "$HEX2" -f "$ELF" -f "$BUILDROOT/self-v2-$ARCH.hex2" \
        --little-endian --architecture "$ARCH" --base-address "$BASE" \
        -o "$BUILDROOT/cc-out-v3-$ARCH") \
        || fail $((SID+5)) "hex2 link v2 ($ARCH) failed"
    chmod +x "$BUILDROOT/cc-out-v3-$ARCH"
    echo "E: cc-out-v3-$ARCH ($(wc -c < "$BUILDROOT/cc-out-v3-$ARCH") bytes)"

    # --- F: fixed-point v2 == v3 -----------------------------------------
    (cd "$M2_PLANET" && "$BUILDROOT/cc-out-v3-$ARCH" --architecture "$ARCH" --expand-includes \
        "${m2_args[@]}" -o "$BUILDROOT/self-v3-$ARCH.M1") \
        || fail $((SID+6)) "v3 self-compile ($ARCH) failed"
    cmp "$BUILDROOT/self-v2-$ARCH.M1" "$BUILDROOT/self-v3-$ARCH.M1" \
        || fail $((SID+6)) "fixed-point broken at $ARCH: v2 != v3"
    echo "F: self-v2-$ARCH == self-v3-$ARCH ($(wc -c < "$BUILDROOT/self-v2-$ARCH.M1") bytes) — fixed-point closure"

    # --- G: end-to-end smoke ---------------------------------------------
    (cd "$M2_PLANET" && "$BUILDROOT/cc-out-v3-$ARCH" --architecture "$ARCH" --expand-includes \
        -f "$BUILDROOT/hello.c" -o "$BUILDROOT/hello-$ARCH.M1") \
        || fail $((SID+7)) "v3 hello.c compile ($ARCH) failed"
    (cd "$M2_PLANET" && "$M1" -f "$DEFS" -f "$LIBC" \
        -f "$BUILDROOT/hello-$ARCH.M1" \
        --little-endian --architecture "$ARCH" \
        -o "$BUILDROOT/hello-$ARCH.hex2") \
        || fail $((SID+7)) "M1 hello ($ARCH) failed"
    (cd "$M2_PLANET" && "$HEX2" -f "$ELF" -f "$BUILDROOT/hello-$ARCH.hex2" \
        --little-endian --architecture "$ARCH" --base-address "$BASE" \
        -o "$BUILDROOT/hello-$ARCH-elf") \
        || fail $((SID+7)) "hex2 hello ($ARCH) failed"
    chmod +x "$BUILDROOT/hello-$ARCH-elf"
    local actual ec
    actual=$("$BUILDROOT/hello-$ARCH-elf"); ec=$?
    [ "$actual" = "Hello from Forth-bootstrapped M2-Planet!" ] \
        || fail $((SID+7)) "hello-$ARCH stdout: '$actual'"
    [ "$ec" = "0" ] || fail $((SID+7)) "hello-$ARCH exit: $ec"
    echo "G: hello-$ARCH-elf ($(wc -c < "$BUILDROOT/hello-$ARCH-elf") bytes) runs, stdout OK, exit 0"
}

# Pre-create the tiny.c and hello.c source files used by all arches.
cat > "$BUILDROOT/tiny.c"  <<'EOF'
int main() { return 42; }
EOF
cat > "$BUILDROOT/hello.c" <<'EOF'
#include <stdio.h>
int main() {
    fputs("Hello from Forth-bootstrapped M2-Planet!\n", stdout);
    return 0;
}
EOF

# ---------------------------------------------------------------------------
step 2 "per-arch self-host fixed-point chains"
# ---------------------------------------------------------------------------
sid=100
for arch in $ARCHES; do
    run_arch_chain "$arch" "$sid"
    sid=$((sid+100))
done

# ---------------------------------------------------------------------------
step 3 "M2-Planet test suite parity (x86, byte-identical to reference)"
# ---------------------------------------------------------------------------
# Tests use relative #include paths that resolve only when CWD = M2-Planet.
ok=0; bothfail=0; differ=0; total=0
pushd "$M2_PLANET" >/dev/null
for d in test/test*; do
    [ -d "$d" ] || continue
    src=$(ls "$d"/*.c 2>/dev/null | head -1 || true)
    [ -z "$src" ] && continue
    total=$((total+1))
    name=$(basename "$d")
    our_rc=0; ref_rc=0
    timeout 30 "$BUILDROOT/cc-out-v1" --architecture x86 --expand-includes \
        -f "$src" -o "$BUILDROOT/test-our.S" 2>/dev/null || our_rc=$?
    timeout 30 "$M2REF" --architecture x86 --expand-includes \
        -f "$src" -o "$BUILDROOT/test-ref.S" 2>/dev/null || ref_rc=$?
    if [ "$our_rc" = "0" ] && [ "$ref_rc" = "0" ]; then
        if cmp -s "$BUILDROOT/test-our.S" "$BUILDROOT/test-ref.S"; then
            ok=$((ok+1))
        else
            echo "  $name: DIFFER"; differ=$((differ+1))
        fi
    elif [ "$our_rc" != "$ref_rc" ]; then
        echo "  $name: BUG (our=$our_rc ref=$ref_rc)"; differ=$((differ+1))
    else
        bothfail=$((bothfail+1))
    fi
done
popd >/dev/null
echo "M2-Planet tests: identical=$ok  both-fail=$bothfail  differ=$differ  (of $total)"
[ "$differ" = "0" ] || fail 3 "$differ M2-Planet tests differ from reference"

echo
echo "All stages passed."
