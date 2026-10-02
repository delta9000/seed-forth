#!/bin/sh
# Host gate for the actual direct K0/K1/ladder entry point. Host Python only
# verifies raw bytes and checks results; seed Forth is the only pre-existing
# compiler executable used by the launcher/recipe. QEMU is a separate test:
#     k1/run-chain.sh --seed-smoke
set -eu
cd "$(dirname "$0")/../.."
ROOT=$(pwd -P)
[ -x ./seed-forth ] || { echo "direct kernel route: build seed-forth first" >&2; exit 1; }
# Only known generated paths in this repository may be cleared or overwritten.
# Prepared C sources are now generated outputs: remove them for a raw start.
[ ! -L build-out ] || { echo "direct kernel route: build-out must not be a symlink" >&2; exit 1; }
for path in build-out/tcc-sources build-out/tcc-bootstrap build-out/pnut-amd64 build-out/amd64-runner build-out/amd64-runner.input \
            build-out/tcc-seed build-out/tcc-seed.partial build-out/tcc-compile.input \
            build-out/tcc-compile.stdout; do
    [ ! -L "$path" ] || { echo "direct kernel route: refusing symlink $path" >&2; exit 1; }
done
python3 tools/tcc_inputs.py
python3 tests/tcc/kernel-route-check.py
rm -rf "$ROOT/build-out/pnut-amd64" "$ROOT/build-out/tcc-sources" "$ROOT/build-out/tcc-bootstrap"
rm -f "$ROOT/build-out/amd64-runner" "$ROOT/build-out/amd64-runner.input"
timeout "${SF_TCC_TIMEOUT:-300}" ./seed-forth < tools/tcc-ladder-start.fth
python3 tests/tcc/kernel-route-check.py --after
python3 tests/tcc/ladder-helpers-check.py
python3 tools/prepare-ladder.py --check
echo "PASS actual direct kernel/ladder host entry (guest execution requires the separate QEMU test)"
