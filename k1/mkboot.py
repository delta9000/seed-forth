#!/usr/bin/env python3
"""Write K0's boot image for the K1 run: k0/mkfs.py's image plus K1's
sources, with tools/k1-boot.recipe appended to tools/amd64.recipe so the
route ends by building K1 with tcc-boot2 and starting it.  mkboot.py OUT"""
import pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "k0"))
import mkfs
extra = {f"k1/{p.name}": p.read_bytes() for p in (ROOT / "k1").iterdir()
         if p.suffix in (".c", ".S", ".h")}
extra["tools/amd64.recipe"] = ((ROOT / "tools/amd64.recipe").read_bytes()
                               + (ROOT / "tools/k1-boot.recipe").read_bytes())
mkfs.write(sys.argv[1], extra)
