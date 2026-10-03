#!/usr/bin/env bash
# Compile a scalar function translation unit to ELF64 ET_REL using Forth.
# No host compiler, assembler, linker or preprocessor is invoked.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SRC=$(realpath "$1")
OUT=$(realpath -m "$2")
shift 2
if [ "$SRC" = "$OUT" ] || [ "$SRC" -ef "$OUT" ]; then
  echo "sysv-compile: source and output must be different files" >&2
  exit 1
fi
for pathname in "$SRC" "$OUT"; do
  if [[ "$pathname" =~ [[:space:]] ]] || [ "${#pathname}" -gt 255 ]; then
    echo "sysv-compile: Forth driver paths must be at most255 bytes without whitespace" >&2
    exit 1
  fi
done
mkdir -p "$(dirname "$OUT")"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
[ -x "$ROOT/seed-forth" ] || "$ROOT/build.sh" >/dev/null
cat >"$T/driver.fth" <<DRIVER
cc-sysv-object-enable
[lit] 8388608 cc-arena-map
create native-output s, $OUT [lit] 0 c,
create native-source s, $SRC
native-source [lit] ${#SRC} cc-prep-source-name
DRIVER
for inc in "$@"; do
  inc=$(realpath "$inc")
  if [[ "$inc" =~ [[:space:]] ]] || [ "${#inc}" -gt 255 ]; then
    echo "sysv-compile: invalid include pathname for Forth driver" >&2
    exit 1
  fi
  printf "create native-include s, %s\nnative-include [lit] %s cc-prep-add-include\n" "$inc" "${#inc}" >>"$T/driver.fth"
done
cat >>"$T/driver.fth" <<DRIVER
: native-main
  cc-load-stdin cc-preprocess cc-out-init cc-globals-init
  cc-sysv-object-program native-output cc-obj-write bye ;
DRIVER
if [ "${SF_NATIVE_DUMP:-0}" = 1 ]; then
cat >>"$T/driver.fth" <<'DRIVER'
: native-dump
  cc-load-stdin cc-preprocess
  native-output [lit] 577 [lit] 420 open
  dup cc-src-buf cc-src-len @ write drop close drop bye ;
native-dump
DRIVER
else
  echo native-main >>"$T/driver.fth"
fi
CC=()
for f in "$ROOT"/[0-9][0-9][0-9]-cc-*.fth; do case "$f" in *120-cc-main.fth|*140-cc-link.fth) ;; *) CC+=("$f");; esac; done
{ cat "$ROOT/010-lib.fth" "${CC[@]}" "$T/driver.fth" "$SRC"; } | "$ROOT/seed-forth" >"$T/compiler.stdout"
if [ -s "$T/compiler.stdout" ]; then
  cat "$T/compiler.stdout" >&2
  echo "sysv-compile: unexpected compiler output (invalid Forth vocabulary)" >&2
  exit 1
fi
chmod 644 "$OUT"
