#!/usr/bin/env bash
# Verification-only pnut-control tests. Build that control first; after
# check-all.sh, pass BUILDROOT=build-out/pnut-amd64-control-check explicitly.
set -euo pipefail
cd "$(dirname "$0")/../.."
W=${BUILDROOT:-$PWD/build-out/pnut-amd64}
python3 tools/prepare-amd64-inputs.py --check
python3 tools/prepare-amd64-exact-patches.py --check
python3 tests/pnut/flatten-includes-check.py "$W/flatten-includes"
python3 tests/pnut/simple-patch-check.py "$W/kit/simple-patch"
python3 tests/pnut/amd64-runner-check.py build-out/amd64-runner --simple-patch "$W/kit/simple-patch"
gcc -std=c99 -Wall -Wextra -Werror -O2 tests/pnut/simple-patch-io.c -o build-out/simple-patch-io
python3 tests/pnut/simple-patch-check.py build-out/simple-patch-io --injected-io
tests/pnut/amd64-isolated-check.sh
