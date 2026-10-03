#!/usr/bin/env bash
# Unchanged GCC4 source and original headers, without host preprocessing.
# Upstream commit944765863eec87a9f37e297994fd2af960397138 and archive pin
# 091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67
# are recorded in gcc64/SOURCES. Host compilation below is an oracle only.
set -euo pipefail
cd "$(dirname "$0")/../.."
source_path=${1:-build-out/direct-gcc-inputs/gcc-source/libiberty/hex.c}
include_dir=${2:-build-out/direct-gcc-inputs/gcc-source/include}
verify_source() {
  local expected=$1 file=$2 actual
  if [ ! -f "$file" ]; then
    echo "SKIP: original pinned GCC input is absent: $file" >&2
    exit 77
  fi
  actual=$(sha256sum "$file")
  if [ "${actual%% *}" != "$expected" ]; then
    echo "FAIL: original GCC input hash mismatch: $file" >&2
    exit 1
  fi
}
verify_source d81852ba26d5b287ec5b7a56345cac48fea9d5d03d32ce9bf58e35317253d702 "$source_path"
verify_source 420bbb597e6d7aad56a4a35aa8208b5e08824c7e980a93e64d69d046b17397f2 "$include_dir/libiberty.h"
verify_source 38f60dc0bdf48f2275be8d4e1f43701fa3415d07a69d1e3c3607ad43336dbff0 "$include_dir/safe-ctype.h"
verify_source 8d761202d371342ceff509b7a07cdbbf0ae767c03e3bd9abe57f35b9b15e6a73 "$include_dir/ansidecl.h"
work=$(mktemp -d /tmp/sf-gcc-hex.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-object-compile.sh "$source_path" "$work/hex.o" runtime/gcc-seed/include "$include_dir"
tests/gcc/sysv-object-compile.sh tests/gcc/sysv-gcc-hex-oracle.c "$work/check.o" runtime/gcc-seed/include "$include_dir"
cat > "$work/start.fth" <<DRIVER
create output s, $work/start.o [lit] 0 c,
cc-sysrt-start-object output cc-obj-write bye
DRIVER
cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 081-cc-object.fth \
  122-cc-sysv-runtime.fth "$work/start.fth" | ./seed-forth >"$work/start.log"
[ ! -s "$work/start.log" ] || { cat "$work/start.log" >&2; exit 1; }
cat > "$work/link.fth" <<DRIVER
create start-object s, $work/start.o [lit] 0 c,
create source-object s, $work/hex.o [lit] 0 c,
create check-object s, $work/check.o [lit] 0 c,
create entry-name s, _start
create output s, $work/check [lit] 0 c,
lnk-init start-object lnk-add-object source-object lnk-add-object
check-object lnk-add-object entry-name [lit] 6 lnk-entry output lnk-link bye
DRIVER
cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 140-cc-link.fth \
  "$work/link.fth" | ./seed-forth >"$work/link.log"
[ ! -s "$work/link.log" ] || { cat "$work/link.log" >&2; exit 1; }
"$work/check"
echo 'PASS: unchanged GCC hex.c plus original headers -> Forth objects/link -> all256 entries and macros'
${CC:-cc} -O2 -fno-builtin -fno-pie -no-pie -I "$include_dir" \
  tests/gcc/sysv-gcc-hex-oracle.c "$work/hex.o" -o "$work/host-check"
"$work/host-check"
echo 'PASS: Forth GCC hex.c object -> independent host header/ABI oracle'
