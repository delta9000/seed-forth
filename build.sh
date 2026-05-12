#!/usr/bin/env bash
# Build seed-forth from 000-seed.hex0.
# Strips ';'-line-comments and whitespace, hex-decodes the rest.
set -euo pipefail
cd "$(dirname "$0")"
sed 's/;.*$//' 000-seed.hex0 | tr -d ' \t\n' | xxd -r -p > seed-forth
chmod +x seed-forth
echo "Built seed-forth ($(wc -c < seed-forth) bytes)"
