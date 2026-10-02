#!/usr/bin/env python3
"""Write the memory image K0 boots with, for loading at FSIMG.

The image is K0's initial state, not an archive K0 parses:

  +0x0000  kernel state (rbp = FSIMG + 0x80; layout in k0.asm)
  +0x1000  PML4, +0x2000 PDPT: the first 4 GiB identity-mapped, 1 GiB pages
  +0x3000  init's argv: { path, NULL }, then the path string
  +0x4000  file table, 24-byte entries: name, nlen, data, size, cap, type
  +TABLE   names and file contents; the file heap starts after them

init runs with stdin open on tools/tcc-ladder-start.fth, stdout and stderr on
the console, and the root as its working directory.

Usage: mkfs.py OUT   (run from the repository root)
Input: the direct-route source inventory and pinned raw archives/libc/tools
from tools/tcc_inputs.py, the built seed-forth, and an empty /tmp.
Source unpacking/exact patching runs in the guest with Forth-built helpers.
"""
import os, struct, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from tcc_inputs import source_tree

FSIMG = 0x50000000
BASE = FSIMG + 0x80
ENTS = FSIMG + 0x4000
MAXENT = 16384
HEAP0 = ENTS + MAXENT * 24
MMAPB = 0x80000000
INIT, STDIN = "seed-forth", "tools/tcc-ladder-start.fth"

def write(out, extra=None):
    """extra maps image paths to bytes: files added, or contents replaced."""
    extra = extra or {}
    repo = source_tree()
    files = sorted(set(repo) | {INIT} | set(extra))
    dirs = {"tmp"}
    for f in files:
        d = os.path.dirname(f)
        while d:
            dirs.add(d)
            d = os.path.dirname(d)
    img = bytearray(HEAP0 - FSIMG)
    heap = bytearray()
    ents = [(0, 0, 0, 0, 2)]                    # entry 0: the root
    addr = {}
    def blob(b):
        a = HEAP0 + len(heap)
        heap.extend(b)
        return a
    for d in sorted(dirs):
        n = d.encode()
        ents.append((blob(n), len(n), 0, 0, 2))
    for f in files:
        n = f.encode()
        data = extra[f] if f in extra else Path(repo.get(f, f)).read_bytes()
        addr[f] = ENTS + 24 * len(ents)
        ents.append((blob(n), len(n), blob(data), len(data), 1))
    assert len(ents) < MAXENT
    assert HEAP0 + len(heap) < MMAPB, "source image overlaps K0 mmap arena"
    for i, (name, nlen, data, size, typ) in enumerate(ents):
        struct.pack_into("<6I", img, ENTS - FSIMG + 24 * i,
                         name, nlen, data, size, size, typ)
    def put(off, fmt, *v):
        struct.pack_into(fmt, img, BASE - FSIMG + off, *v)
    put(-112, "<I", ENTS + 24 * len(ents))      # G_END
    put(-104, "<I", HEAP0 + len(heap))          # G_HEAP
    put(-96, "<I", MMAPB)                       # G_BUMP
    put(88, "<6I", addr[STDIN], 0, 1, 0, 1, 0)  # P_FDS: fd 0, 1, 2
    struct.pack_into("<Q", img, 0x1000, FSIMG + 0x2000 + 3)
    for i in range(4):
        struct.pack_into("<Q", img, 0x2000 + 8 * i, (i << 30) | 0x83)
    struct.pack_into("<QQ", img, 0x3000, FSIMG + 0x3010, 0)
    img[0x3010:0x3010 + len(INIT) + 1] = INIT.encode() + b"\0"
    with open(out, "wb") as o:
        o.write(img + heap)
    print(f"{out}: {len(files)} files, {len(dirs)} dirs, "
          f"{len(img) + len(heap)} bytes")

if __name__ == "__main__":
    write(sys.argv[1])
