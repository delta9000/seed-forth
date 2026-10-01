#!/usr/bin/env python3
"""Write a K0 boot image (k0/mkfs.py's format) whose init is K1.

K0 execs k1; K1 takes over the machine, imports the same file table and
reads its arguments (after "--", without the leading "k1") from /k1.args.  Usage (from the repository root):

  mkimg.py OUT [--add HOST=IMG ...] [--no-repo] -- k1-args...

--add copies a host file or directory tree into the image at IMG.
Default contents: the files k0/mkfs.py packs (git-tracked files outside
book/ and vendor/, the pinned pnut files, seed-forth), plus k1 itself.
"""
import os, struct, subprocess, sys

FSIMG = 0x50000000
BASE = FSIMG + 0x80
ENTS = FSIMG + 0x4000
MAXENT = 65536
HEAP0 = ENTS + MAXENT * 24
MMAPB = 0x80000000

def tracked():
    out = subprocess.run(["git", "ls-files", "-s"], check=True,
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        meta, path = line.split("\t", 1)
        if meta.split()[0] in ("100644", "100755"):
            yield path

def main():
    argv = sys.argv[1:]
    out = argv.pop(0)
    k1args = argv[argv.index("--") + 1:] if "--" in argv else ["k1"]
    opts = argv[:argv.index("--")] if "--" in argv else argv
    files = {}                                  # image path -> host path
    if "--no-repo" not in opts:
        for f in tracked():
            if not f.startswith(("book/", "vendor/")):
                files[f] = f
        for l in open("tools/amd64-inputs.sha256"):
            files[l.split()[1]] = l.split()[1]
        files["seed-forth"] = "seed-forth"
    out_dir = os.environ.get("K1_OUT", "build-out/k1")
    files["k1"] = os.path.join(out_dir, "k1")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "k1.args"), "w") as a:
        a.write("".join(x + "\n" for x in k1args[1:]))
    files["k1.args"] = os.path.join(out_dir, "k1.args")
    i = 0
    while i < len(opts):
        if opts[i] == "--add":
            host, img = opts[i + 1].split("=", 1)
            img = img.strip("/")
            if os.path.isdir(host):
                for dp, dn, fn in os.walk(host):
                    for n in fn:
                        h = os.path.join(dp, n)
                        if os.path.isfile(h) and not os.path.islink(h):
                            files[os.path.join(img, os.path.relpath(h, host))] = h
            else:
                files[img] = host
            i += 2
        else:
            i += 1
    dirs = {"tmp"}
    for f in files:
        d = os.path.dirname(f)
        while d:
            dirs.add(d)
            d = os.path.dirname(d)
    img = bytearray(HEAP0 - FSIMG)
    heap = bytearray()
    ents = [(0, 0, 0, 0, 2)]
    def blob(b):
        a = HEAP0 + len(heap)
        heap.extend(b)
        return a
    for d in sorted(dirs):
        n = d.encode()
        ents.append((blob(n), len(n), 0, 0, 2))
    for f in sorted(files):
        n, data = f.encode(), open(files[f], "rb").read()
        ents.append((blob(n), len(n), blob(data), len(data), 1))
    assert len(ents) < MAXENT, len(ents)
    for i, (name, nlen, data, size, typ) in enumerate(ents):
        struct.pack_into("<6I", img, ENTS - FSIMG + 24 * i, name, nlen, data, size, size, typ)
    def put(off, fmt, *v):
        struct.pack_into(fmt, img, BASE - FSIMG + off, *v)
    put(-112, "<I", ENTS + 24 * len(ents))      # G_END
    put(-104, "<I", HEAP0 + len(heap))          # G_HEAP
    put(-96, "<I", MMAPB)                       # G_BUMP
    put(88, "<6I", 0, 0, 1, 0, 1, 0)            # fd 0 closed, 1 and 2 console
    struct.pack_into("<Q", img, 0x1000, FSIMG + 0x2000 + 3)
    for i in range(4):
        struct.pack_into("<Q", img, 0x2000 + 8 * i, (i << 30) | 0x83)
    # K0 execs "k1" (its init argv: { path, NULL } then the path at +0x10);
    # K1 reads its own arguments from /k1.args, one per line.
    struct.pack_into("<QQ", img, 0x3000, FSIMG + 0x3010, 0)
    img[0x3010:0x3013] = b"k1\0"
    assert HEAP0 + len(heap) < 0xC0000000, "image too large"
    with open(out, "wb") as o:
        o.write(img + heap)
    print(f"{out}: {len(files)} files, {len(img) + len(heap)} bytes")

main()
