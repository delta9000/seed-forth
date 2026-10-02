#!/bin/sh
# Preprocess-only checks: never writes the shared /tmp/cc-out compiler output.
set -eu
cd "$(dirname "$0")/../.."
exec python3 tests/tcc/prep-check.py "$@"
