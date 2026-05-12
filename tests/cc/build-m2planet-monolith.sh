#!/usr/bin/env bash
# Build an M2-Planet monolith and compile it with our cc.
#
# Concatenates the 4 headers + 8 .c files in dependency order, stripping
# each .c file's quote-includes (since our preprocessor has no #ifndef/#endif
# support, every #include "cc.h" would re-expand the header and duplicate
# struct/typedef declarations).  Headers are emitted once at the top.
#
# Output: /tmp/cc-out is the seed-forth-built M2-Planet-compatible compiler
# used by the Stage-A parity and bootstrap-chain checks.
set -euo pipefail
cd "$(dirname "$0")/../.."

M2=${M2_PLANET:-vendor/M2-Planet}
MONOLITH=/tmp/m2planet-monolith.c
OUT=/tmp/cc-out

strip_forth() { sed -e 's/\\.*$//' -e 's/([^)]*)//g' | grep -v '^[[:space:]]*$'; }

[ -f "$M2/cc.c" ] || { echo "FAIL: M2_PLANET=$M2 is not initialized (run git submodule update --init --recursive)" >&2; exit 1; }
[ -f "$M2/M2libc/bootstrappable.c" ] || { echo "FAIL: M2_PLANET/M2libc is not initialized (run git submodule update --init --recursive)" >&2; exit 1; }

# Build seed-forth if missing.
[ -x seed-forth ] || ./build.sh >/dev/null

# Step 1: monolith = headers (once) + .c files (with quote-includes stripped).
{
  cat "$M2/cc.h" "$M2/cc_globals.h" "$M2/cc_emit.h" "$M2/gcc_req.h"
  for f in M2libc/bootstrappable.c cc_globals.c cc_strings.c cc_types.c cc_macro.c cc_reader.c \
           cc_emit.c cc_core.c cc.c; do
    sed -e '/^#include[[:space:]]*"/d' -e '/^#define TRUE 1/d' -e '/^#define FALSE 0/d' "$M2/$f"
  done
} > "$MONOLITH"

# Step 2: feed (stripped vocab + monolith) to seed-forth.
TMP_VOCAB=$(mktemp)
trap 'rm -f "$TMP_VOCAB"' EXIT
cat [0-9][0-9][0-9]-*.fth | strip_forth > "$TMP_VOCAB"

rm -f "$OUT"
cat "$TMP_VOCAB" "$MONOLITH" | ./seed-forth
rc=$?

if [ ! -f "$OUT" ]; then
    echo "FAIL: compile produced no output (rc=$rc)"
    exit 1
fi
chmod +x "$OUT"
echo "OK: $(wc -c < $OUT) bytes at $OUT (compiler rc=$rc)"
