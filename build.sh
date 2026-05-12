#!/usr/bin/env bash
# Build seed-forth from 000-seed.hex0 using stage0-posix's hex0-seed —
# the same 229-byte trust-root assembler Guix uses for its Full Source
# Bootstrap.  No xxd / vim dependency.
#
# Initial bootstrap (no seed-forth, no stage0 yet) is an out-of-band
# act: any hex0 assembler reproduces 000-seed.hex0 byte-for-byte,
# including stage0's own hex0, GNU coreutils via
# `sed 's/[;#].*$//g' 000-seed.hex0 | xxd -r -p`, or hand-keying.
# Once you have stage0-posix's hex0-seed, this script is hermetic.
set -euo pipefail
cd "$(dirname "$0")"

HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}

if [ ! -x "$HEX0" ]; then
    cat >&2 <<EOF
build.sh: hex0 assembler not found at $HEX0
Initialize the submodule:
    git submodule update --init vendor/stage0-posix
    git -C vendor/stage0-posix submodule update --init bootstrap-seeds
or set HEX0=/path/to/hex0 to use an alternative assembler.
EOF
    exit 1
fi

"$HEX0" 000-seed.hex0 seed-forth
chmod +x seed-forth
echo "Built seed-forth ($(wc -c < seed-forth) bytes) using $HEX0"
