#!/usr/bin/env python3
"""Write K0's boot image for the K1 run.  mkboot.py OUT [--direct]

Default (TinyCC route): k0/mkfs.py's image plus K1's sources, with
tools/k1-boot.recipe appended to tools/tcc.recipe so the route ends by
building K1 with tcc-boot2 and starting it.

--direct (direct-GCC route, no TinyCC): only what seed Forth needs to build
K1 (k1/direct_inputs.py), with init reading tools/k1-direct-start.fth and
tools/k1-direct-boot.recipe appended to tools/k1-direct.recipe, so K0 builds
K1 with the Forth compiler, tools/obj-asm.fth and the Forth linker, then
starts it."""
import pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "k0"))
sys.path.insert(0, str(ROOT / "k1"))
import mkfs
if len(sys.argv) == 3 and sys.argv[2] == "--direct":
    from direct_inputs import k0_tree
    extra = {"tools/k1-direct.recipe": (ROOT / "tools/k1-direct.recipe").read_bytes()
             + (ROOT / "tools/k1-direct-boot.recipe").read_bytes()}
    mkfs.write(sys.argv[1], extra, repo=k0_tree(), stdin="tools/k1-direct-start.fth")
    sys.exit(0)
if len(sys.argv) != 2:
    sys.exit("usage: mkboot.py OUT [--direct]")
extra = {f"k1/{p.name}": p.read_bytes() for p in (ROOT / "k1").iterdir()
         if p.suffix in (".c", ".S", ".h")}
extra["tools/tcc.recipe"] = ((ROOT / "tools/tcc.recipe").read_bytes()
                               + (ROOT / "tools/k1-boot.recipe").read_bytes())
mkfs.write(sys.argv[1], extra)
