#!/usr/bin/env bash
# First unchanged GCC source unit, not a complete direct-GCC bootstrap.
# Upstream gcc-mirror release gcc-4.0.4, commit
# 944765863eec87a9f37e297994fd2af960397138, original archive SHA256
# 091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67.
# Source provenance is pinned in gcc64/SOURCES. Never rewrite this input.
set -euo pipefail
cd "$(dirname "$0")/../.."
source_path=${1:-build-out/direct-gcc-inputs/gcc-source/libiberty/ffs.c}
expected_sha=514a4bfc11ca70e48d818c9dccfb13b3c7f502371b0b54d0b13c5dec7220ecec
if [ ! -f "$source_path" ]; then
  echo "SKIP: provide original pinned GCC libiberty/ffs.c path" >&2
  exit 77
fi
actual_sha=$(sha256sum "$source_path")
if [ "${actual_sha%% *}" != "$expected_sha" ]; then
  echo 'FAIL: source differs from original pinned GCC ffs.c' >&2
  exit 1
fi
work=$(mktemp -d /tmp/sf-gcc-ffs.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-object-compile.sh "$source_path" "$work/ffs.o"
tests/gcc/sysv-object-compile.sh tests/gcc/sysv-gcc-ffs-oracle.c "$work/check.o"
cat > "$work/start.fth" <<DRIVER
create output s, $work/start.o [lit] 0 c,
cc-sysrt-start-object output cc-obj-write bye
DRIVER
cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 081-cc-object.fth \
  122-cc-sysv-runtime.fth "$work/start.fth" | ./seed-forth >"$work/start.log"
[ ! -s "$work/start.log" ] || { cat "$work/start.log" >&2; exit 1; }
cat > "$work/link.fth" <<DRIVER
create start-object s, $work/start.o [lit] 0 c,
create source-object s, $work/ffs.o [lit] 0 c,
create check-object s, $work/check.o [lit] 0 c,
create entry-name s, _start
create output s, $work/check
[lit] 0 c,
lnk-init start-object lnk-add-object source-object lnk-add-object
check-object lnk-add-object entry-name [lit] 6 lnk-entry output lnk-link bye
DRIVER
cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 140-cc-link.fth \
  "$work/link.fth" | ./seed-forth >"$work/link.log"
[ ! -s "$work/link.log" ] || { cat "$work/link.log" >&2; exit 1; }
"$work/check"
echo 'PASS: original GCC ffs.c -> Forth object -> Forth link -> 100032 comparisons'
# An independent host-built harness repeats the same comparisons against
# the Forth object. These reference bytes never enter the bootstrap proof.
${CC:-cc} -O2 -fno-builtin -fno-pie -no-pie \
  tests/gcc/sysv-gcc-ffs-oracle.c "$work/ffs.o" -o "$work/host-check"
"$work/host-check"
echo 'PASS: original GCC ffs.c Forth object -> host ABI oracle -> 100032 comparisons'
