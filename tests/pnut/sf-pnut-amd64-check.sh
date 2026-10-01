#!/usr/bin/env bash
# Convenience launcher and optional verification-only GCC oracle.
# The authoritative shell-free route is, from the repository root:
#   ./seed-forth < tools/amd64-start.fth
# After that exec the only programs are the seed and its descendants. Sources,
# Linux, and initial fd/cwd setup remain outside this executable closure.
# See HOST-TOOLS.md for the exact boundary and isolated-root verification.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
if [ ! -f vendor/pnut/pnut.c ] || [ ! -f vendor/pnut/kit/tcc-0.9.27.tar.gz ]; then
    echo 'sf-pnut-amd64-check: SKIP: vendor/pnut or its TinyCC tarball is missing'
    exit 77
fi
[ -x seed-forth ] || ./build.sh >/dev/null
BUILDROOT=${BUILDROOT:-$ROOT/build-out/pnut-amd64}
case $BUILDROOT in /*) ;; *) BUILDROOT=$ROOT/$BUILDROOT ;; esac
# Private /tmp is launch preparation, not a compiler/source transformation.
# Keep the mounted directory outside BUILDROOT, which the runner resets.
if [ -z "${SF_PNUT64_IN_PRIVATE_TMP:-}" ]; then
    case "$ROOT/ $BUILDROOT/" in /tmp/*|*' /tmp/'*) private=0 ;; *) private=1 ;; esac
    if [ "$private" = 1 ] && unshare -rm true 2>/dev/null; then
        mkdir -p "$ROOT/build-out/amd64-private-tmp"
        export SF_PNUT64_IN_PRIVATE_TMP=1 BUILDROOT
        exec unshare -rm bash -c 'mount --bind "$1" /tmp && exec bash "$2"' \
            _ "$ROOT/build-out/amd64-private-tmp" "$ROOT/tests/pnut/sf-pnut-amd64-check.sh"
    fi
fi
if [ "${SF_PNUT64_GCC_ORACLE:-0}" = 1 ]; then
    ./seed-forth < tools/amd64-start.fth 8<<< "${SF_PNUT64_REPIN:-0}" 9<<< "$BUILDROOT"
    exec bash tests/pnut/sf-pnut-amd64-oracle.sh "$BUILDROOT"
fi
exec ./seed-forth < tools/amd64-start.fth 8<<< "${SF_PNUT64_REPIN:-0}" 9<<< "$BUILDROOT"
