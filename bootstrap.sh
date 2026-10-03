#!/usr/bin/env bash
# bootstrap.sh — the GCC-free build: hex0-seed -> seed-forth -> M2-Planet,
# M1 and hex2 -> self-hosted M2-Planet at its fixed point.
#
# Platform: x86-64 (amd64) Linux only.  Takes ~30 s on a current x86-64.
#
# WHAT THIS TRUSTS (everything that touches a byte of the outputs):
#   - vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed, the
#     229-byte stage0-posix trust root (or $HEX0), which assembles
#     000-seed.hex0;
#   - this repository's sources: 000-seed.hex0, 010-lib.fth, the compiler
#     020-cc-arena.fth .. 120-cc-main.fth, and the assembler 130-asm.fth;
#   - the pinned upstream C and M1 sources in vendor/M2-Planet (incl. its
#     M2libc) and vendor/mescc-tools (incl. its M2libc) — source only;
#     no binary from either tree is executed;
#   - the host's Linux kernel and bash.  bash itself composes the M2-Planet
#     monolith (a line filter that drops M2-Planet's `#include "..."` and
#     `#define TRUE/FALSE` lines; no sed), and `cat` concatenates inputs.
#     seed-forth runs the compiler with cwd = vendor/M2-Planet, so the one
#     quote-include left in the monolith (cc.h's `#include "cc_globals.h"`)
#     reads the pinned upstream header, not the copy under tests/cc/.
#     `mkdir`, `rm` and `mv` only create directories, delete stale files and
#     rename outputs; they never produce file contents.
#   - Not in provenance, used only to check and report: `cmp`, `wc`,
#     `sha256sum`.  Optional isolation: when `unshare -rm` works, each
#     seed-forth run gets a private /tmp (the Forth programs write the fixed
#     paths /tmp/cc-out and /tmp/asm-out), so concurrent runs can't collide.
#   No C compiler, assembler or linker from the host is ever run.  Nothing
#   here is compared against a GCC-built reference: see verify.sh for that.
#
# WHAT THIS PROVES (fails loudly otherwise):
#   1. hex0-seed assembles a 1,772-byte seed-forth.
#   2. seed-forth, running the Forth C compiler, compiles M2-Planet into
#      cc-out-v1 (a Forth-built ELF).
#   3. cc-out-v1 compiles M2-Planet to self-v1-amd64.M1, and 130-asm.fth
#      (the Forth M1+hex2 assembler) turns that into cc-out-v2-fasm.
#   4. cc-out-v2-fasm compiles mescc-tools' M1 and hex2; 130-asm.fth
#      assembles them into the M1 and hex2 binaries (the method of
#      tests/asm/mescc-tools-check.sh, without its GCC comparison).
#   5. Those M1+hex2 assemble self-v1-amd64.M1 into cc-out-v2, which must
#      be byte-identical to cc-out-v2-fasm (two assemblers agree).
#   6. v2 compiles M2-Planet -> self-v2-amd64.M1 -> M1+hex2 -> cc-out-v3;
#      v3 compiles M2-Planet -> self-v3-amd64.M1, which must equal
#      self-v2-amd64.M1 byte for byte (the self-hosting fixed point).
#   7. v3 recompiles M1 and hex2 from source, assembled by themselves;
#      the results must equal step 4's M1 and hex2 (tool fixed point).
#   8. v3 compiles hello.c, M1+hex2 link it, and it runs.
#
# Output: $BUILDROOT/out (default ./build-out/out; wiped at the start of
# every run, never reused).  Intermediate inputs go to $BUILDROOT/work.
#
# Env overrides:
#   BUILDROOT    default ./build-out
#   HEX0         default vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
#   M2_PLANET    default vendor/M2-Planet
#   MESCC_TOOLS  default vendor/mescc-tools
#   PRIVATE_TMP  auto (default) | 0 (always use the real /tmp)

set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD

HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}
M2_PLANET=${M2_PLANET:-vendor/M2-Planet}
MESCC_TOOLS=${MESCC_TOOLS:-vendor/mescc-tools}
BUILDROOT=${BUILDROOT:-$ROOT/build-out}
PRIVATE_TMP=${PRIVATE_TMP:-auto}

T0=$SECONDS
step() { printf '\n=== %s: %s  [t=%ds]\n' "$1" "$2" $((SECONDS - T0)); }
fail() { printf 'bootstrap: FAIL: %s\n' "$1" >&2; exit 1; }
ok()   { printf '  ok: %s\n' "$1"; }

# ---------------------------------------------------------------------------
step 0 "prerequisites"
# ---------------------------------------------------------------------------
case "${OSTYPE:-}/${HOSTTYPE:-}" in
    linux*/x86_64) ;;
    *) fail "amd64 Linux only (this host: OSTYPE=${OSTYPE:-?} HOSTTYPE=${HOSTTYPE:-?})" ;;
esac
[ -x "$HEX0" ] || fail "hex0 assembler not found at $HEX0 (git submodule update --init --recursive)"
[ -f "$M2_PLANET/cc.c" ] && [ -f "$M2_PLANET/M2libc/bootstrappable.c" ] \
    || fail "$M2_PLANET (and its M2libc) not initialized (git submodule update --init --recursive)"
[ -f "$MESCC_TOOLS/M1-macro.c" ] && [ -f "$MESCC_TOOLS/M2libc/bootstrappable.c" ] \
    || fail "$MESCC_TOOLS (and its M2libc) not initialized (git submodule update --init --recursive)"

mkdir -p "$BUILDROOT"
HEX0=$(cd "$(dirname "$HEX0")" && pwd)/$(basename "$HEX0")
M2_PLANET=$(cd "$M2_PLANET" && pwd)
MESCC_TOOLS=$(cd "$MESCC_TOOLS" && pwd)
BUILDROOT=$(cd "$BUILDROOT" && pwd)
OUT=$BUILDROOT/out
WORK=$BUILDROOT/work
rm -rf "$OUT" "$WORK"          # no stale artifacts, ever
mkdir -p "$OUT" "$WORK/tmp"

# The Forth compiler writes /tmp/cc-out and the Forth assembler /tmp/asm-out
# (paths baked into 120-cc-main.fth and 130-asm.fth).  Give each run a
# private /tmp (bind-mounted from $WORK/tmp) when the kernel allows it.
if [ "$PRIVATE_TMP" != 0 ] && unshare -rm bash -c 'mount --bind "$1" /tmp' _ "$WORK/tmp" 2>/dev/null; then
    FTMP=$WORK/tmp
    ok "seed-forth runs get a private /tmp ($FTMP)"
else
    FTMP=/tmp
    ok "unshare -rm unavailable: seed-forth writes the shared /tmp/cc-out, /tmp/asm-out"
fi
SEED=$OUT/seed-forth

# run_forth <dir> <stdin-file> <cc-out|asm-out> <dest>
#   Run seed-forth in <dir> (the C preprocessor resolves `#include "x"`
#   relative to the cwd) on <stdin-file>; move the program's fixed /tmp
#   output to <dest>.  The Forth itself creates that file mode 0755.
run_forth() {
    local dir=$1 in=$2 name=$3 dest=$4 rc=0
    rm -f "$FTMP/$name"
    if [ "$FTMP" = /tmp ]; then
        (cd "$dir" && "$SEED" < "$in") || rc=$?
    else
        # stdin and seed-forth (fd 3) are opened before the mount, so they
        # stay reachable even when $BUILDROOT itself is under /tmp.
        (cd "$dir" && unshare -rm bash -c \
            'mount --bind "$1" /tmp && exec /proc/self/fd/3 3<&3' \
            _ "$FTMP" < "$in" 3< "$SEED") || rc=$?
    fi
    [ "$rc" = 0 ] || fail "seed-forth exited $rc on $(basename "$in")"
    [ -f "$FTMP/$name" ] || fail "seed-forth wrote no /tmp/$name for $(basename "$in")"
    mv "$FTMP/$name" "$dest"
    [ -x "$dest" ] || fail "$dest is not executable (umask?)"
}

# forth_asm <name> <program.M1> <dest>: 130-asm.fth assembles M2-Planet's
# amd64 defs + ELF header + libc + <program.M1> into an ELF at <dest>.
forth_asm() {
    local name=$1 m1=$2 dest=$3
    local L=$M2_PLANET/M2libc/amd64
    { cat 010-lib.fth 130-asm.fth
      printf 'asm-main\n'
      cat "$L/amd64_defs.M1" "$L/ELF-amd64.hex2" "$L/libc-full.M1" "$m1"
    } > "$WORK/forth-asm-$name.in"
    run_forth "$WORK" "$WORK/forth-asm-$name.in" asm-out "$dest"
}

# m1_hex2 <program.M1> <dest>: the bootstrapped M1 + hex2 link an amd64 ELF.
m1_hex2() {
    local m1=$1 dest=$2
    local L=$M2_PLANET/M2libc/amd64
    "$OUT/M1" --little-endian --architecture amd64 \
        -f "$L/amd64_defs.M1" -f "$L/libc-full.M1" -f "$m1" \
        -o "$WORK/$(basename "$dest").hex2" || fail "M1 on $(basename "$m1")"
    "$OUT/hex2" --little-endian --architecture amd64 --base-address 0x00600000 \
        -f "$L/ELF-amd64.hex2" -f "$WORK/$(basename "$dest").hex2" \
        -o "$dest" || fail "hex2 on $(basename "$m1")"
    [ -x "$dest" ] || fail "$dest is not executable"
}

# The M2-Planet self-compile source set (as in M2-Planet's makefile).
m2_args=()
for s in M2libc/bootstrappable.c cc_reader.c cc_strings.c cc_types.c \
         cc_emit.c cc_core.c cc_macro.c cc.c cc.h cc_globals.c gcc_req.h; do
    m2_args+=( -f "$s" )
done
# self_compile <compiler> <out.M1>
self_compile() {
    (cd "$M2_PLANET" && "$1" --architecture amd64 --expand-includes \
        "${m2_args[@]}" -o "$2") || fail "$(basename "$1") failed to compile M2-Planet"
}
# build_tool <compiler> <out.M1> <sources...>: compile mescc-tools C sources.
build_tool() {
    local cc=$1 out=$2; shift 2
    local a=() s
    for s in "$@"; do a+=( -f "$s" ); done
    (cd "$MESCC_TOOLS" && "$cc" --architecture amd64 --expand-includes \
        "${a[@]}" -o "$out") || fail "$(basename "$cc") failed on $*"
}
M1_SRCS=(M2libc/bootstrappable.c stringify.c M1-macro.c)
HEX2_SRCS=(M2libc/bootstrappable.c hex2_linker.c hex2_word.c hex2.c)

# ---------------------------------------------------------------------------
step 1 "hex0-seed assembles 000-seed.hex0 -> seed-forth"
# ---------------------------------------------------------------------------
"$HEX0" 000-seed.hex0 "$SEED" || fail "hex0-seed failed"
[ "$(wc -c < "$SEED")" = 1772 ] || fail "seed-forth is not 1772 bytes"
[ -x "$SEED" ] || fail "seed-forth is not executable"
ok "seed-forth: 1772 bytes"

# ---------------------------------------------------------------------------
step 2 "seed-forth compiles M2-Planet -> cc-out-v1"
# ---------------------------------------------------------------------------
# The monolith: M2-Planet's four headers once, then each .c file with its
# quote-includes dropped and the duplicate TRUE/FALSE defines dropped.  (It
# was built this way before the Forth preprocessor had #ifndef; it is kept
# because cc-out-v1's bytes, which REPRODUCIBLE.md pins, depend on it.)  Same bytes as the sed filter in
# tests/cc/build-m2planet-monolith.sh, done in bash so no sed is trusted.
strip_c() {
    local line re='^#include[[:space:]]*"'
    while IFS= read -r line || [ -n "$line" ]; do
        [[ $line =~ $re ]] && continue
        [[ $line == '#define TRUE 1'* || $line == '#define FALSE 0'* ]] && continue
        printf '%s\n' "$line"
    done < "$1"
}
{
    cat "$M2_PLANET/cc.h" "$M2_PLANET/cc_globals.h" "$M2_PLANET/cc_emit.h" "$M2_PLANET/gcc_req.h"
    for f in M2libc/bootstrappable.c cc_globals.c cc_strings.c cc_types.c \
             cc_macro.c cc_reader.c cc_emit.c cc_core.c cc.c; do
        strip_c "$M2_PLANET/$f"
    done
} > "$WORK/m2planet-monolith.c"
cat 010-lib.fth $(tools/compiler-layers.sh) "$WORK/m2planet-monolith.c" > "$WORK/cc-v1.in"
run_forth "$M2_PLANET" "$WORK/cc-v1.in" cc-out "$OUT/cc-out-v1"
ok "cc-out-v1: $(wc -c < "$OUT/cc-out-v1") bytes (Forth-compiled M2-Planet)"

# ---------------------------------------------------------------------------
step 3 "cc-out-v1 compiles M2-Planet; 130-asm.fth assembles it -> cc-out-v2-fasm"
# ---------------------------------------------------------------------------
self_compile "$OUT/cc-out-v1" "$OUT/self-v1-amd64.M1"
ok "self-v1-amd64.M1: $(wc -c < "$OUT/self-v1-amd64.M1") bytes"
forth_asm m2 "$OUT/self-v1-amd64.M1" "$OUT/cc-out-v2-fasm"
ok "cc-out-v2-fasm: $(wc -c < "$OUT/cc-out-v2-fasm") bytes"

# ---------------------------------------------------------------------------
step 4 "cc-out-v2-fasm compiles mescc-tools; 130-asm.fth assembles -> M1, hex2"
# ---------------------------------------------------------------------------
build_tool "$OUT/cc-out-v2-fasm" "$WORK/M1.M1"   "${M1_SRCS[@]}"
build_tool "$OUT/cc-out-v2-fasm" "$WORK/hex2.M1" "${HEX2_SRCS[@]}"
forth_asm M1   "$WORK/M1.M1"   "$OUT/M1"
forth_asm hex2 "$WORK/hex2.M1" "$OUT/hex2"
ok "M1: $(wc -c < "$OUT/M1") bytes, hex2: $(wc -c < "$OUT/hex2") bytes"

# ---------------------------------------------------------------------------
step 5 "M1 + hex2 assemble self-v1-amd64.M1 -> cc-out-v2 (== cc-out-v2-fasm?)"
# ---------------------------------------------------------------------------
m1_hex2 "$OUT/self-v1-amd64.M1" "$OUT/cc-out-v2"
cmp "$OUT/cc-out-v2" "$OUT/cc-out-v2-fasm" \
    || fail "M1+hex2 and 130-asm.fth disagree on self-v1-amd64.M1"
ok "cc-out-v2 == cc-out-v2-fasm ($(wc -c < "$OUT/cc-out-v2") bytes)"

# ---------------------------------------------------------------------------
step 6 "v2 -> v3 self-host; fixed point self-v2-amd64.M1 == self-v3-amd64.M1"
# ---------------------------------------------------------------------------
self_compile "$OUT/cc-out-v2" "$OUT/self-v2-amd64.M1"
m1_hex2 "$OUT/self-v2-amd64.M1" "$OUT/cc-out-v3"
self_compile "$OUT/cc-out-v3" "$OUT/self-v3-amd64.M1"
cmp "$OUT/self-v2-amd64.M1" "$OUT/self-v3-amd64.M1" \
    || fail "fixed point broken: self-v2-amd64.M1 != self-v3-amd64.M1"
ok "self-v2-amd64.M1 == self-v3-amd64.M1 ($(wc -c < "$OUT/self-v3-amd64.M1") bytes)"
if cmp -s "$OUT/self-v1-amd64.M1" "$OUT/self-v2-amd64.M1"; then
    ok "self-v1 == self-v2 as well"
else
    ok "self-v1 != self-v2 (expected: v1 was compiled with C's logical &&, v2 with M2-Planet's bitwise &&; see REPRODUCIBLE.md)"
fi

# ---------------------------------------------------------------------------
step 7 "tool fixed point: v3 + M1/hex2 rebuild M1 and hex2 -> same bytes"
# ---------------------------------------------------------------------------
build_tool "$OUT/cc-out-v3" "$WORK/M1-gen2.M1"   "${M1_SRCS[@]}"
build_tool "$OUT/cc-out-v3" "$WORK/hex2-gen2.M1" "${HEX2_SRCS[@]}"
m1_hex2 "$WORK/M1-gen2.M1"   "$WORK/M1-gen2"
m1_hex2 "$WORK/hex2-gen2.M1" "$WORK/hex2-gen2"
cmp "$WORK/M1-gen2"   "$OUT/M1"   || fail "M1 rebuilt by itself differs"
cmp "$WORK/hex2-gen2" "$OUT/hex2" || fail "hex2 rebuilt by itself differs"
ok "M1 and hex2 reproduce themselves byte for byte"

# ---------------------------------------------------------------------------
step 8 "smoke: v3 compiles hello.c; M1 + hex2 link; it runs"
# ---------------------------------------------------------------------------
printf '#include <stdio.h>\nint main() {\n    fputs("Hello from Forth-bootstrapped M2-Planet!\\n", stdout);\n    return 0;\n}\n' \
    > "$WORK/hello.c"
(cd "$M2_PLANET" && "$OUT/cc-out-v3" --architecture amd64 --expand-includes \
    -f "$WORK/hello.c" -o "$WORK/hello.M1") || fail "v3 failed on hello.c"
m1_hex2 "$WORK/hello.M1" "$OUT/hello"
got=$("$OUT/hello") || fail "hello exited non-zero"
[ "$got" = "Hello from Forth-bootstrapped M2-Planet!" ] || fail "hello printed '$got'"
ok "hello: $got"

# ---------------------------------------------------------------------------
step 9 "done — sha256 of $OUT"
# ---------------------------------------------------------------------------
(cd "$OUT" && sha256sum seed-forth cc-out-v1 self-v1-amd64.M1 cc-out-v2 \
    self-v2-amd64.M1 cc-out-v3 M1 hex2) | tee "$OUT/SHA256SUMS"
echo
echo "bootstrap: PASS in $((SECONDS - T0))s — no GCC in the provenance of anything in $OUT"
