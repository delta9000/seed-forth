#!/usr/bin/env python3
"""Offline manifest authoring/checking; never invoked by the bootstrap."""
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
paths = subprocess.check_output(["git", "-C", str(pnut), "ls-files", "-z"]).decode().split("\0")
lines = []
for path in filter(None, paths):
    if any(char.isspace() for char in path):
        raise SystemExit(f"manifest path contains whitespace: {path!r}")
    content = (pnut / path).read_bytes()
    committed = subprocess.check_output(["git", "-C", str(pnut), "show", f"{pin}:{path}"])
    if content != committed:
        raise SystemExit(f"working tree differs from pinned source: {path}")
    lines.append(f"{hashlib.sha256(content).hexdigest()}  vendor/pnut/{path}\n")
expected = "".join(lines)
target = root / "tools/amd64-inputs.sha256"
if args.check:
    if target.read_text() != expected:
        raise SystemExit("amd64 source manifest is stale")
else:
    target.write_text(expected)
print(f"amd64-inputs: {len(lines)} pinned source files verified")
