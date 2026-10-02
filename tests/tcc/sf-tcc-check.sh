#!/usr/bin/env bash
# Direct seed Forth -> TinyCC -> fixed point. Python prepares pinned sources
# and verifies the continuation; only Forth/generated compilers translate C.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
mkdir -p build-out
if [ -n "${BUILDROOT:-}" ]; then
  W=$(realpath -m "$BUILDROOT")
  if [ -e "$W" ]; then
    echo "sf-tcc-check: BUILDROOT must be a new directory: $W" >&2
    exit 1
  fi
  mkdir -p "$W"
else
  W=$(mktemp -d "$ROOT/build-out/forth-tcc.XXXXXX")
fi
printf 'sf-tcc-check: work directory: %s\n' "$W"
python3 tests/tcc/prep-stage-sources.py "$W/sources" >"$W/source-preparation.log"
SF_NATIVE_FLOATBITS=1 tests/tcc/compile-native.sh \
  "$W/sources/direct-input.c" "$W/tcc-seed" "$W/sources/libc64/include" \
  >"$W/forth.log" 2>"$W/forth.err"
python3 tests/tcc/downstream-check.py --repo "$ROOT" --kit "$W/sources" \
  --seed "$W/tcc-seed" --dest "$W/verified" >"$W/downstream.log" 2>&1
cat "$W/downstream.log"
want=7411c326d30ff5a0ebadfe36d6218b6e46d2e8357f76d3a003e74ed9aee2fc3a
got=$(sha256sum "$W/tcc-seed"); got=${got%% *}
if [ "$got" != "$want" ]; then
  echo "sf-tcc-check: seed hash changed: $got (expected $want); review before re-pinning" >&2
  exit 1
fi
printf 'sf-tcc-check: PASS: direct TinyCC seed %s\n' "$got"
printf 'sf-tcc-check: handoff: %s\n' "$W/verified/kit/build/tcc-boot2"
