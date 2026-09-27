#!/usr/bin/env bash
# build-gcc-refs.sh <dir> — build the GCC reference binaries, fresh, into <dir>.
#
#   <dir>/m2-ref     M2-Planet   (vendor/M2-Planet, flags from its makefile)
#   <dir>/M1-ref     mescc-tools M1   (vendor/mescc-tools, flags from its makefile)
#   <dir>/hex2-ref   mescc-tools hex2
#
# TRUSTS: the host gcc and the pinned vendor sources.  These binaries exist
# only to be *compared against* (verify.sh, stage-a-check.sh, tests/asm/*);
# nothing in bootstrap.sh's output is built with them.
#
# Always rebuilds: <dir> is wiped first, so a reference left over from an
# older pin, another STAGE0_COMPAT mode, or a different compiler is never
# silently reused.  (GCC output is not reproducible across GCC versions, so
# pinning a hash is not an option; rebuilding takes ~2 s.)  Builds straight
# from source with gcc — never via `make`, whose bin/ in the submodule
# could be stale — and writes nothing into vendor/.
#
# Env: M2_PLANET (default vendor/M2-Planet), MESCC_TOOLS (default
# vendor/mescc-tools), CC (default gcc).
set -euo pipefail
cd "$(dirname "$0")/../.."

[ $# = 1 ] || { echo "usage: $0 <dir>" >&2; exit 2; }
M2_PLANET=${M2_PLANET:-vendor/M2-Planet}
MESCC_TOOLS=${MESCC_TOOLS:-vendor/mescc-tools}
CC=${CC:-gcc}

fail() { printf 'build-gcc-refs: FAIL: %s\n' "$1" >&2; exit 1; }
command -v "$CC" >/dev/null || fail "$CC not on PATH"
[ -f "$M2_PLANET/cc.c" ] && [ -f "$M2_PLANET/M2libc/bootstrappable.c" ] \
    || fail "$M2_PLANET not initialized (git submodule update --init --recursive)"
[ -f "$MESCC_TOOLS/M1-macro.c" ] && [ -f "$MESCC_TOOLS/M2libc/bootstrappable.c" ] \
    || fail "$MESCC_TOOLS not initialized (git submodule update --init --recursive)"

rm -rf "$1"
mkdir -p "$1"
D=$(cd "$1" && pwd)

(cd "$M2_PLANET" && "$CC" -D_GNU_SOURCE -O0 -std=c99 \
    M2libc/bootstrappable.c cc_reader.c cc_strings.c cc_types.c cc_emit.c \
    cc_core.c cc_macro.c cc.c cc.h cc_globals.c gcc_req.h -o "$D/m2-ref") \
    || fail "gcc M2-Planet"
(cd "$MESCC_TOOLS" && "$CC" -D_GNU_SOURCE -std=c99 -fno-common \
    M1-macro.c stringify.c M2libc/bootstrappable.c -o "$D/M1-ref") \
    || fail "gcc M1"
(cd "$MESCC_TOOLS" && "$CC" -D_GNU_SOURCE -std=c99 -fno-common \
    hex2.c hex2_linker.c hex2_word.c M2libc/bootstrappable.c -o "$D/hex2-ref") \
    || fail "gcc hex2"
echo "build-gcc-refs: m2-ref, M1-ref, hex2-ref rebuilt with $("$CC" --version | head -1) in $D"
