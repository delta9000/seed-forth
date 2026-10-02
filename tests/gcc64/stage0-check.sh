#!/usr/bin/env bash
# Test the direct TinyCC handoff pins and reusable-kit safety without fetching GCC.
# Run tests/tcc/kernel-route-check.sh first to produce the default input kit.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
SOURCE=${GCC64_STAGE0_TEST_SOURCE:-$ROOT/build-out/pnut-amd64}
SOURCE=$(cd "$SOURCE" && pwd)
WORK=$(mktemp -d "$ROOT/build-out/gcc64-stage0-check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
run_stage0() {
  BUILDROOT="$1" GCC64_STAGE0="$2" GCC64_CACHE="$WORK/empty-cache" \
    gcc64/run-gcc64.sh stage0
}
run_stage0 "$WORK/reuse" "$SOURCE" >"$WORK/reuse.log" 2>&1
run_stage0 "$WORK/reuse" "$WORK/reuse/tccboot" >"$WORK/inplace.log" 2>&1
cmp "$SOURCE/kit/build/tcc-boot2" "$WORK/reuse/tccboot/kit/build/tcc-boot2"
test -z "$(find "$WORK/empty-cache" -type f -print -quit)"
for artifact in build/tcc-boot2 build/boot2-lib/crt1.o build/boot2-lib/libc.a \
                build/boot2-lib/tcc/libtcc1.a; do
  # Restore each artifact after its negative probe; never change the source kit.
  printf 'bad pin\n' >"$WORK/reuse/tccboot/kit/$artifact"
  status=0
  run_stage0 "$WORK/negative" "$WORK/reuse/tccboot" >"$WORK/negative.log" 2>&1 || status=$?
  test "$status" = 1
  grep -F "kit/$artifact differs" "$WORK/negative.log" >/dev/null
  test ! -e "$WORK/negative/tccboot"
  cp "$SOURCE/kit/$artifact" "$WORK/reuse/tccboot/kit/$artifact"
done
echo 'PASS: GCC stage0 reuses pinned direct kit, preserves in-place kit, rejects all four changed pins and fetches no GCC source'
