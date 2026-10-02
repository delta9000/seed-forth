#!/bin/sh
# Run the seed route and then tools/ladder.recipe on the host, from a clean
# build-out/pnut-amd64.  Run from the repository root.
set -eu
cd "$(dirname "$0")/.."
ulimit -f 2097152                      # no single file over 2 GiB
python3 tools/prepare-ladder.py
python3 tools/tcc_inputs.py
rm -rf build-out/pnut-amd64 build-out/tcc-bootstrap build-out/tcc-sources build-out/amd64-runner build-out/amd64-runner.input
./seed-forth < tools/tcc-ladder-start.fth
timeout 3600 build-out/amd64-runner --recipe tools/ladder.recipe
