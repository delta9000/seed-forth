#!/usr/bin/env python3
"""Offline manifest authoring/checking; never invoked by the bootstrap.

The manifest lists only the pnut files the amd64 route reads: pnut's
native x86_64 backend, kit's bintools, libtcc1 and tcc tarball, and the
portable libc.  The shell and awk backends, docs, benchmarks, examples
and kit/scavenge-shells are never compiled or read, so they are neither
pinned nor staged.  USED came from an strace of the route (every staged
file opened for reading); a file missing from it fails the route.
tools/amd64-libc.sha256 is the portable_libc slice, staged as libc64.
"""
import argparse
import hashlib
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
pnut = root / "vendor/pnut"
pin = "abc34a5207b1373d0a4e3dcb3d3d6df6e22ae23d"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
head = subprocess.check_output(["git", "-C", str(pnut), "rev-parse", "HEAD"], text=True).strip()
if head != pin:
    raise SystemExit(f"pnut must be the pinned {pin}, got {head}")
USED = """
elf.c
env.c
exe.c
kit/bintools-libc.c
kit/bintools/bintools-base.c
kit/bintools/cat.c
kit/bintools/chmod.c
kit/bintools/cp.c
kit/bintools/crc.c
kit/bintools/mkdir.c
kit/bintools/puff.c
kit/bintools/puff.h
kit/bintools/sha256sum.c
kit/bintools/simple-patch.c
kit/bintools/ungz.c
kit/bintools/untar.c
kit/config.h
kit/libtcc1.c
kit/tcc-0.9.27.tar.gz
pnut.c
portable_libc/include/crt1.h
portable_libc/include/ctype.h
portable_libc/include/errno.h
portable_libc/include/fcntl.h
portable_libc/include/inttypes.h
portable_libc/include/math.h
portable_libc/include/pnut_lib.h
portable_libc/include/setjmp.h
portable_libc/include/signal.h
portable_libc/include/stdarg.h
portable_libc/include/stdint.h
portable_libc/include/stdio.h
portable_libc/include/stdlib.h
portable_libc/include/string.h
portable_libc/include/sys/mman.h
portable_libc/include/sys/stat.h
portable_libc/include/sys/time.h
portable_libc/include/sys/types.h
portable_libc/include/time.h
portable_libc/include/unistd.h
portable_libc/libc.c
portable_libc/src/crt1.c
portable_libc/src/ctype.c
portable_libc/src/errno.c
portable_libc/src/math.c
portable_libc/src/pnut_lib.c
portable_libc/src/setjmp.c
portable_libc/src/signal.c
portable_libc/src/stdio.c
portable_libc/src/stdlib.c
portable_libc/src/string.c
portable_libc/src/sys/mman.c
portable_libc/src/time.c
portable_libc/src/unistd.c
portable_libc/test-libc.c
x86.c
""".split()
tracked = set(subprocess.check_output(["git", "-C", str(pnut), "ls-files", "-z"]).decode().split("\0"))
missing = [p for p in USED if p not in tracked]
if missing:
    raise SystemExit(f"not tracked in pnut: {missing}")
paths = USED
lines = []
for path in filter(None, paths):
    if any(char.isspace() for char in path):
        raise SystemExit(f"manifest path contains whitespace: {path!r}")
    content = (pnut / path).read_bytes()
    committed = subprocess.check_output(["git", "-C", str(pnut), "show", f"{pin}:{path}"])
    if content != committed:
        raise SystemExit(f"working tree differs from pinned source: {path}")
    lines.append(f"{hashlib.sha256(content).hexdigest()}  vendor/pnut/{path}\n")
outputs = {
    root / "tools/amd64-inputs.sha256": "".join(lines),
    root / "tools/amd64-libc.sha256": "".join(
        l for l in lines if "  vendor/pnut/portable_libc/" in l),
}
for target, expected in outputs.items():
    if args.check:
        if target.read_text() != expected:
            raise SystemExit(f"{target.name} is stale")
    else:
        target.write_text(expected)
print(f"amd64-inputs: {len(lines)} pinned source files verified")
