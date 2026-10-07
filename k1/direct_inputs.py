"""Image inventories for K1 on the direct-GCC route (no TinyCC).

k0_tree(): what K0 needs to build K1 from the seed (tools/k1-direct-start.fth
and tools/k1-direct.recipe); k0/mkfs.py adds seed-forth itself.
k1_tree(smoke, linux): K1's starting tree for k1/direct-smoke.recipe or, without
smoke, k1/direct.recipe: sources only, plus hex0-seed (the only executable,
added by k1/mkdisk.py) and, for the full route, the pinned tarballs the
plumbing stages unpack; with linux, also what k1/direct-linux.recipe needs
after bash 2.05b.  Paths map image names to host files.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _files(*patterns):
    out = {}
    for pattern in patterns:
        for p in sorted(ROOT.glob(pattern)):
            if p.is_file() and not p.is_symlink() and p.name != ".git" \
                    and "__pycache__" not in p.parts:
                out[str(p.relative_to(ROOT))] = p
    return out


def _layers():
    return _files("[0-9][0-9][0-9]-*.fth")


def k0_tree():
    tree = _layers()
    tree.update(_files("tools/amd64-runner.c", "tools/amd64-syscalls.fth",
                       "tools/k1-direct-start.fth", "tools/k1-direct.recipe",
                       "tools/obj-asm.fth", "k1/*.c", "k1/*.h", "k1/*.S",
                       "k1/k1-asm.fth", "k1/boot/*.fth"))
    return tree


def k1_tree(smoke, linux=False):
    tree = {"000-seed.hex0": ROOT / "000-seed.hex0"}
    tree.update(_layers())
    tree.update(_files("tools/seed-cc-start.fth", "tools/seed-cc-boot/*.fth",
                       "tools/seed-cc.c", "tools/seed-ar.c", "tools/seed-tool.h",
                       "runtime/gcc-seed/**/*", "vendor/mescc-tools/Kaem/*",
                       "vendor/mescc-tools/M2libc/bootstrappable.*",
                       "vendor/stage0-posix/mescc-tools-extra/*.c",
                       "vendor/stage0-posix/mescc-tools-extra/M2libc/bootstrappable.*",
                       "k1/direct-smoke.kaem", "k1/tests/direct-smoke.*"))
    if not smoke:
        tree.update(_files("tools/*", "plumbing/**/*", "gcc-direct/lexer-inputs/**/*",
                           "build-out/plumbing-inputs/*", "build-out/lexer-inputs/archives/*"))
    if linux:
        # After bash 2.05b (k1/direct-linux.recipe): the GCC chain, the late tools,
        # gcc64's bridge to gcc-10.5.0 and Linux.  build-out/distfiles holds the
        # archives of k1/chain-inputs.sha256; chain.SOURCES' plain binutils tar
        # is the one input that is not a release archive as published.
        tree.update(_files("k1/direct-full.sh", "gcc-direct/*.sh", "gcc-direct/patches/**/*", "ladder/**/*",
                           "gcc64/*", "patches/**/*", "tests/gcc/stage-c-hello.*",
                           "tests/gcc64/**/*", "build-out/distfiles/*",
                           "build-out/stage-b-inputs/binutils-2.30.tar"))
    missing = [n for n in ("vendor/mescc-tools/M2libc/bootstrappable.c",
                           "vendor/stage0-posix/mescc-tools-extra/M2libc/bootstrappable.c")
               if n not in tree]
    if missing:
        raise SystemExit(f"missing {missing}: initialize the M2libc submodules")
    return tree
