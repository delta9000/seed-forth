#!/usr/bin/env python3
"""Write a newc cpio archive (an initramfs).  Host-side test helper.
Usage: mkcpio.py OUT IMGPATH=HOSTFILE... ; /dev/console is always added."""
import os, sys

def ent(out, name, mode, data=b"", rdev=(0, 0), ino=[1]):
    n = name.encode() + b"\0"
    hdr = "070701" + "".join("%08X" % v for v in (
        ino[0], mode, 0, 0, 1, 0, len(data), 0, 0, rdev[0], rdev[1], len(n), 0))
    ino[0] += 1
    b = hdr.encode() + n
    b += b"\0" * (-len(b) % 4)
    b += data + b"\0" * (-len(data) % 4)
    out.write(b)

with open(sys.argv[1], "wb") as o:
    ent(o, "dev", 0o40755)
    ent(o, "dev/console", 0o20600, rdev=(5, 1))
    for a in sys.argv[2:]:
        img, host = a.split("=", 1)
        ent(o, img.strip("/"), 0o100755, open(host, "rb").read())
    ent(o, "TRAILER!!!", 0)
