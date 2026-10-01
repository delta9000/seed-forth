#!/bin/sh
# Run the seed route and then tools/ladder.recipe on the host, from a clean
# build-out/pnut-amd64.  Run from the repository root.
set -eu
cd "$(dirname "$0")/.."
ulimit -f 2097152                      # no single file over 2 GiB
python3 tools/prepare-ladder.py
rm -rf build-out/pnut-amd64 build-out/amd64-runner build-out/amd64-runner.input
./seed-forth < tools/amd64-start.fth 2>&1 | tail -1
timeout 3600 build-out/amd64-runner --recipe tools/ladder.recipe
