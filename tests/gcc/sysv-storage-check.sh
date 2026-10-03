#!/usr/bin/env bash
# Production object bytes come from Forth; host code only checks the boundary.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d /tmp/sf-sysv-storage.XXXXXX)
trap 'rm -rf "$work"' EXIT
tests/gcc/sysv-object-compile.sh tests/gcc/sysv-storage.c "$work/storage.o"
${CC:-cc} -O2 -Wall -Wextra -fno-pie -no-pie \
  tests/gcc/sysv-storage-host.c "$work/storage.o" -o "$work/check"
"$work/check"
readelf -r "$work/storage.o" > "$work/relocations.txt"
rg -q 'R_X86_64_64' "$work/relocations.txt"
rg -q 'pair \+ 8' "$work/relocations.txt"
rg -q 'rows \+ 14' "$work/relocations.txt"
echo 'PASS: serialized address addends match field and multidimensional-array offsets'
# Repeat with every executable input produced by Forth, including providers.
tests/gcc/sysv-object-compile.sh tests/gcc/sysv-storage-provider.c "$work/provider.o"
tests/gcc/sysv-object-compile.sh tests/gcc/sysv-storage-entry.c "$work/entry.o"
cat > "$work/start.fth" <<DRIVER
create output s, $work/start.o [lit] 0 c,
cc-sysrt-start-object output cc-obj-write bye
DRIVER
cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 081-cc-object.fth \
  122-cc-sysv-runtime.fth "$work/start.fth" | ./seed-forth >"$work/start.log"
[ ! -s "$work/start.log" ] || { cat "$work/start.log" >&2; exit 1; }
cat > "$work/link.fth" <<DRIVER
create start-object s, $work/start.o [lit] 0 c,
create storage-object s, $work/storage.o [lit] 0 c,
create provider-object s, $work/provider.o [lit] 0 c,
create entry-object s, $work/entry.o [lit] 0 c,
create entry-name s, _start
create output s, $work/forth-check [lit] 0 c,
lnk-init start-object lnk-add-object storage-object lnk-add-object
provider-object lnk-add-object entry-object lnk-add-object
entry-name [lit] 6 lnk-entry output lnk-link bye
DRIVER
cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 140-cc-link.fth \
  "$work/link.fth" | ./seed-forth >"$work/link.log"
[ ! -s "$work/link.log" ] || { cat "$work/link.log" >&2; exit 1; }
"$work/forth-check"
echo 'PASS: cross-translation-unit storage and pointer relocations with the Forth linker'
