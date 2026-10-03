#!/usr/bin/env bash
# Original pinned obstack source and header; all production bytes are Forth.
set -euo pipefail
cd "$(dirname "$0")/../.."
source_path=${1:-build-out/direct-gcc-inputs/gcc-source/libiberty/obstack.c}
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
verify_source cb6dd25eccbee998d6e01bb6c57e8b5d2b0abf37cdcd12fd1a5ca3ae4f8ddcc7 "$source_path"
verify_source 099f6cf0cb38cadf0040b4c0e235026401004104e96349d9211daaa6e3a38aa4 "$include_dir/obstack.h"
work=$(mktemp -d /tmp/sf-gcc-obstack.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 tools/gcc-direct-cc.py -I "$include_dir" \
  tests/gcc/sysv-gcc-obstack.c "$source_path" -o "$work/check"
"$work/check"
echo 'PASS: unchanged GCC obstack.c, original header, both callback modes, growth/copy and frees through Forth objects/runtime/link'
