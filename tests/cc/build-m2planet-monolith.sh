#!/usr/bin/env bash
# Build an M2-Planet monolith and compile it with our cc.
#
# Concatenates the 4 headers + 8 .c files in dependency order, stripping
# each .c file's quote-includes and the duplicate TRUE/FALSE defines.
# Headers are emitted once at the top.  (This predates the preprocessor's
# #ifndef support, when every #include "cc.h" re-expanded the header; it
# is kept so the monolith, and so cc-out-v1, stay the same bytes.)
#
# Output: /tmp/cc-out is the seed-forth-built M2-Planet-compatible compiler
# used by the Stage-A parity and bootstrap-chain checks (the monolith itself
# goes to /tmp/m2planet-monolith.c).  The Forth compiler always writes the
# fixed path /tmp/cc-out, so two concurrent runs collide there.
#
# Env:
#   CC_OUT=<path>
#     Write the compiler to <path> instead, and keep the shared /tmp out of
#     it: the monolith goes to <path>.monolith.c, and seed-forth runs with a
#     private /tmp (bind-mounted from <path>.tmp via `unshare -rm`, as
#     bootstrap.sh does) when the kernel allows it; otherwise it falls back
#     to the shared /tmp/cc-out and moves the result.  stage-a-check.sh
#     uses this.  Unset: the /tmp/cc-out behaviour the book describes.
#   STAGE0_COMPAT=1
#     Replace the (Architecture & ARCH_FAMILY_X86) guard in
#     write_{add,sub}_immediate with constant 0 before compiling, so cc-out-v1
#     deliberately omits the BYTE-immediate x86 stack/offset optimization.
#     The guard is `(Architecture & ARCH_FAMILY_X86) && (...)`: an ISO C
#     compiler (GCC, our Forth compiler) evaluates it as 8 && 1 = 1, but
#     M2-Planet-family compilers (cc_amd64, M2, M2-Planet) compile `&&` as
#     bitwise AND, 8 & 1 = 0, so every M2-Planet-built M2-Planet skips the
#     optimization.  With the patch, cc-out-v1's self-host output equals an
#     M2-Planet-built M2-Planet's (stage0 route or this repo's v2/v3).
#     Default (unset) keeps the optimization on and matches the GCC-built
#     reference instead.  tests/cc/stage0-check.sh proves both; see
#     REPRODUCIBLE.md "Stage0 cross-check and STAGE0_COMPAT".
set -euo pipefail
cd "$(dirname "$0")/../.."

M2=${M2_PLANET:-vendor/M2-Planet}
MONOLITH=/tmp/m2planet-monolith.c
OUT=/tmp/cc-out
CC_OUT=${CC_OUT:-}
if [ -n "$CC_OUT" ]; then
    mkdir -p "$(dirname "$CC_OUT")"
    CC_OUT=$(cd "$(dirname "$CC_OUT")" && pwd)/$(basename "$CC_OUT")
    MONOLITH=$CC_OUT.monolith.c
    PTMP=$CC_OUT.tmp
    rm -rf "$PTMP" "$CC_OUT"
    mkdir -p "$PTMP"
    if unshare -rm sh -c 'mount --bind "$1" /tmp' _ "$PTMP" 2>/dev/null; then
        OUT=$PTMP/cc-out
    else
        rmdir "$PTMP"; PTMP=
    fi
fi

[ -f "$M2/cc.c" ] || { echo "FAIL: M2_PLANET=$M2 is not initialized (run git submodule update --init --recursive)" >&2; exit 1; }
[ -f "$M2/M2libc/bootstrappable.c" ] || { echo "FAIL: M2_PLANET/M2libc is not initialized (run git submodule update --init --recursive)" >&2; exit 1; }

# Build seed-forth if missing.
[ -x seed-forth ] || ./build.sh >/dev/null

# Optional patch set applied to the monolith.  Empty by default.
patch_args=()
if [ "${STAGE0_COMPAT:-0}" = "1" ]; then
    patch_args+=(
        -e 's@(Architecture & ARCH_FAMILY_X86) && (reg == REGISTER_STACK || reg == REGISTER_ZERO)@0 /* STAGE0_COMPAT: see REPRODUCIBLE.md */@'
        -e 's@(Architecture & ARCH_FAMILY_X86) && (reg == REGISTER_ZERO)@0 /* STAGE0_COMPAT: see REPRODUCIBLE.md */@'
    )
fi

# Step 1: monolith = headers (once) + .c files (with quote-includes stripped).
{
  cat "$M2/cc.h" "$M2/cc_globals.h" "$M2/cc_emit.h" "$M2/gcc_req.h"
  for f in M2libc/bootstrappable.c cc_globals.c cc_strings.c cc_types.c cc_macro.c cc_reader.c \
           cc_emit.c cc_core.c cc.c; do
    sed -e '/^#include[[:space:]]*"/d' -e '/^#define TRUE 1/d' -e '/^#define FALSE 0/d' \
        "${patch_args[@]}" "$M2/$f"
  done
} > "$MONOLITH"

# Step 2: feed (vocab + monolith) to seed-forth.  The Forth goes in as-is;
# the seed's reader skips \ and ( ) comments itself.
rm -f "$OUT"
rc=0
if [ -n "${PTMP:-}" ]; then
    # stdin and seed-forth (fd 3) are opened before the mount, so they stay
    # reachable even when CC_OUT itself is under /tmp.
    cat 010-lib.fth $(tools/compiler-layers.sh) "$MONOLITH" \
        | unshare -rm sh -c 'mount --bind "$1" /tmp && exec /proc/self/fd/3 3<&3' \
            _ "$PTMP" 3< ./seed-forth || rc=$?
else
    cat 010-lib.fth $(tools/compiler-layers.sh) "$MONOLITH" | ./seed-forth || rc=$?
fi

if [ "$rc" != 0 ] || [ ! -f "$OUT" ]; then
    echo "FAIL: compile produced no output (rc=$rc)"
    exit 1
fi
if [ -n "$CC_OUT" ]; then
    mv "$OUT" "$CC_OUT"
    [ -z "${PTMP:-}" ] || rm -rf "$PTMP"
    OUT=$CC_OUT
fi
chmod +x "$OUT"
echo "OK: $(wc -c < "$OUT") bytes at $OUT (compiler rc=$rc)"
