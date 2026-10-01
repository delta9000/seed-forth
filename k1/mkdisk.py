#!/usr/bin/env python3
"""Write K1's input disk: the chain root's starting tree as one archive.

  mkdisk.py OUT

The tree is what tools/chain-root.sh puts in its root -- hex0-seed (the only
executable), 000-seed.hex0, the Forth and C sources, tools/, ladder/,
patches/, tests/, gcc64/ and every tarball in build-out/distfiles -- plus
/k1.args and /k1.recipe, which tell K1 what to run.  Format: see k1/ata.c.
"""
import os, pathlib, struct, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
HEX0 = ROOT / "vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed"
S_IFDIR, S_IFREG = 0o040000, 0o100000

def tree():
    files = [ROOT / "000-seed.hex0"] + list(ROOT.glob("[0-9][0-9][0-9]-*.fth"))
    for d in ("tools", "ladder", "patches/amd64/exact", "patches/gcc64", "patches/ladder",
              "tests/pnut/amd64", "tests/gcc64", "gcc64"):
        files += [p for p in (ROOT / d).rglob("*") if p.is_file()]
    files += [ROOT / l.split()[1] for l in (ROOT / "tools/amd64-inputs.sha256").read_text().splitlines()]
    out = {str(p.relative_to(ROOT)): (p, 0o644) for p in files}
    for p in sorted((ROOT / "build-out/distfiles").iterdir()):
        out["build-out/distfiles/" + p.name] = (p, 0o644)
    out["hex0-seed"] = (HEX0, 0o755)
    return out

def main():
    dest = sys.argv[1]
    files = tree()
    extra = {"k1.args": b"/k0/build-out/amd64-runner\n--recipe\n/k1.recipe\n",
             "k1.recipe": (ROOT / "k1/k1.recipe").read_bytes()}
    dirs = {"build-out", "tmp", "proc"}
    for name in list(files) + list(extra):
        d = os.path.dirname(name)
        while d:
            dirs.add(d)
            d = os.path.dirname(d)
    total = 0
    with open(dest, "wb") as o:
        o.write(b"K1DISK1\0")
        def rec(name, mode, data_iter, size):
            n = name.encode()
            o.write(struct.pack("<IIQ", len(n), mode, size) + n)
            for chunk in data_iter:
                o.write(chunk)
            o.write(b"\0" * (-o.tell() % 8))
        for d in sorted(dirs, key=lambda d: (d.count("/"), d)):
            rec(d, S_IFDIR | 0o755, [], 0)
        for name in sorted(files):
            p, mode = files[name]
            size = p.stat().st_size
            def chunks(p=p):
                with open(p, "rb") as f:
                    while True:
                        b = f.read(1 << 20)
                        if not b:
                            return
                        yield b
            rec(name, S_IFREG | mode, chunks(), size)
            total += size
        for name, data in extra.items():
            rec(name, S_IFREG | 0o644, [data], len(data))
        o.write(struct.pack("<IIQ", 0, 0, 0))
        o.write(b"\0" * (-o.tell() % 512))
    print(f"{dest}: {len(files) + len(extra)} files, {total >> 20} MiB")

main()
