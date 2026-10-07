#!/usr/bin/env python3
"""Write K1's input disk: the chain root's starting tree as one archive.

  mkdisk.py OUT [--seed-smoke | --direct-smoke | --direct] [--jobs N]

The tree is what tools/chain-root.sh puts in its root -- hex0-seed (the only
executable), 000-seed.hex0, the Forth and C sources, tools/, ladder/,
patches/, tests/, gcc64/, the pinned raw TinyCC archive/libc/tool sources,
and every tarball in build-out/distfiles -- plus
/k1.args and /k1.recipe, which tell K1 what to run.  Format: see k1/ata.c.

--direct-smoke and --direct are the direct-GCC route (no TinyCC): the tree is
k1/direct_inputs.py's and /k1.recipe is k1/direct-smoke.recipe or
k1/direct.recipe.
"""
import argparse, os, pathlib, struct, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
HEX0 = ROOT / "vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed"
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "k1"))
S_IFDIR, S_IFREG = 0o040000, 0o100000

def tree(seed_smoke=False):
    from tcc_inputs import source_tree
    out = {name: (path, 0o644) for name, path in source_tree().items()}
    if not seed_smoke:
        for p in sorted((ROOT / "build-out/distfiles").iterdir()):
            out["build-out/distfiles/" + p.name] = (p, 0o644)
    out["hex0-seed"] = (HEX0, 0o755)
    return out


def direct_tree(smoke):
    from direct_inputs import k1_tree
    out = {name: (path, 0o644) for name, path in k1_tree(smoke).items()}
    out["hex0-seed"] = (HEX0, 0o755)
    return out

def positive_jobs(value):
    if not value.isascii() or not value.isdecimal() or not 1 <= int(value) <= 256:
        raise argparse.ArgumentTypeError("jobs must be an integer from 1 to 256")
    return int(value)


def guest_recipe(seed_smoke=False, jobs=None):
    """Render JOBS explicitly: the recipe runner intentionally supplies no env."""
    recipe = ROOT / ("k1/seed.recipe" if seed_smoke else "k1/k1.recipe")
    data = recipe.read_bytes()
    if jobs is None or seed_smoke:
        return data
    jobs = positive_jobs(str(jobs))
    text = data.decode()
    for stage, bindir in ((10, "/build-out/pnut-amd64/usr/bin"),
                          (11, "/usr/bin"), (12, "/usr/bin")):
        original = f"{bindir}/bash /ladder/stage{stage}.sh"
        replacement = f"{bindir}/env JOBS={jobs} {original}"
        if text.count(original) != 1:
            raise ValueError(f"expected exactly one guest stage{stage} command")
        text = text.replace(original, replacement)
    return text.encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output")
    parser.add_argument("--seed-smoke", action="store_true",
                        help="rebuild the direct seed route under K1, without later ladder distfiles")
    parser.add_argument("--direct-smoke", action="store_true",
                        help="direct-GCC route: seed-cc, seed-ar and kaem under K1 (k1/direct-smoke.recipe)")
    parser.add_argument("--direct", action="store_true",
                        help="direct-GCC route: the seed to bash 2.05b under K1 (k1/direct.recipe)")
    parser.add_argument("--jobs", type=positive_jobs,
                        help="pass this make job count explicitly into guest stages 10-12")
    args = parser.parse_args()
    dest = args.output
    if args.seed_smoke + args.direct_smoke + args.direct > 1:
        parser.error("choose one of --seed-smoke, --direct-smoke and --direct")
    if args.direct_smoke or args.direct:
        if args.jobs is not None:
            parser.error("--jobs applies to the TinyCC route's stages 10-12")
        files = direct_tree(args.direct_smoke)
        recipe = ROOT / ("k1/direct-smoke.recipe" if args.direct_smoke else "k1/direct.recipe")
        recipe = recipe.read_bytes()
    else:
        files = tree(args.seed_smoke)
        recipe = guest_recipe(args.seed_smoke, args.jobs)
    extra = {"k1.args": b"/k0/build-out/amd64-runner\n--recipe\n/k1.recipe\n",
             "k1.recipe": recipe}
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

if __name__ == "__main__":
    main()
