#!/usr/bin/env python3
"""Authoring/checking tool, never run by the bootstrap recipe.

Turn gcc64's early patches into exact-match fixtures for simple-patch, so
the runner can apply them with no patch program:

  tcc.manifest     patches/gcc64/tcc/*, tcc-simple/*, then patches/ladder/tcc/*, on the route's
                   tcc-0.9.27 tree (kit and amd64 fixtures already applied)
  bridge.manifest  patches/gcc64/libc64/01-bridge.diff, on the route's libc64
  musl.manifest    patches/gcc64/musl-1.1.24/*, on the musl-1.1.24 tarball,
                   except 05-lb-makefile.patch: it changes only the
                   Makefile, which the runner's musl recipe does not use

Paths in each manifest are relative to where the recipe applies it: the
kit directory for tcc and bridge, the musl source root for musl.
--check verifies without changing files.
"""
import argparse
import hashlib
from pathlib import Path
import re
import tarfile

ROOT = Path(__file__).resolve().parents[1]
PNUT = ROOT / "vendor/pnut"
AMD64 = ROOT / "patches/amd64/exact"
G = ROOT / "patches/gcc64"
OUT = G / "exact"
MUSL = ROOT / "build-out/distfiles/musl-1.1.24.tar.gz"
sha = lambda data: hashlib.sha256(data).hexdigest()
outputs = {}


def untar(path, strip):
    files = {}
    with tarfile.open(path) as archive:
        for m in archive.getmembers():
            if m.isfile():
                name = m.name[len(strip):] if strip else m.name
                files[name] = archive.extractfile(m).read()
    return files


def apply_manifest(files, manifest, fixtures):
    for row in manifest.read_text().splitlines():
        op, source, target, before, after, pre, post = row.split()
        if op == "copy":
            files[target] = (fixtures / source).read_bytes()
            continue
        b = (fixtures / before).read_bytes()
        a = (fixtures / after).read_bytes()
        assert sha(files[source]) == pre, row
        files[target] = files[source].replace(b, a, 1)
        assert sha(files[target]) == post, row


class Group:
    def __init__(self, name, files):
        self.name, self.files, self.rows, self.n = name, files, [], 0

    def replace(self, path, before, after):
        original = self.files[path]
        first = original.find(before)
        if not before or first < 0 or original.find(before, first + 1) >= 0:
            raise ValueError(f"{self.name}: hunk not unique in {path}")
        changed = original[:first] + after + original[first + len(before):]
        self.n += 1
        stem = f"{self.name}-{self.n:02d}"
        outputs[stem + ".before"] = before
        outputs[stem + ".after"] = after
        self.rows.append(f"replace {path} {path} {stem}.before {stem}.after "
                         f"{sha(original)} {sha(changed)}\n")
        self.files[path] = changed

    def diff(self, patch, prefix=""):
        lines = patch.read_bytes().splitlines(keepends=True)
        i, target = 0, None
        while i < len(lines):
            line = lines[i]
            if line.startswith(b"+++ "):
                name = line[4:].split(b"\t")[0].strip().decode()
                target = prefix + name.split("/", 1)[1]        # -p1
            elif line.startswith(b"@@ "):
                m = re.fullmatch(rb"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@[^\n]*\n", line)
                old, new = int(m[2] or b"1"), int(m[4] or b"1")
                before, after = [], []
                i += 1
                while i < len(lines) and lines[i][:1] in (b" ", b"-", b"+", b"\n"):
                    row = lines[i]
                    if row.startswith((b"--- ", b"+++ ")):
                        break
                    if row == b"\n":                            # blank context line
                        row = b" \n"
                    if row[:1] in (b" ", b"-"):
                        before.append(row[1:])
                    if row[:1] in (b" ", b"+"):
                        after.append(row[1:])
                    if len(before) == old and len(after) == new:
                        i += 1
                        break
                    i += 1
                if len(before) != old or len(after) != new:
                    raise ValueError(f"hunk count mismatch: {patch}")
                if i < len(lines) and lines[i].startswith(b"\\"):
                    raise ValueError(f"no-newline annotation: {patch}")
                self.replace(target, b"".join(before), b"".join(after))
                continue
            i += 1

    def done(self):
        outputs[self.name + ".manifest"] = "".join(self.rows).encode()


# The route's trees, rebuilt from the pinned inputs and its own fixtures.
kit = {"tcc-0.9.27/" + k.split("/", 1)[1]: v
       for k, v in untar(PNUT / "kit/tcc-0.9.27.tar.gz", "").items()}
for path in (PNUT / "portable_libc").rglob("*"):
    if path.is_file():
        kit["libc64/" + str(path.relative_to(PNUT / "portable_libc"))] = path.read_bytes()
for m in ("kit", "tcc", "libc"):
    apply_manifest(kit, AMD64 / f"{m}.manifest", AMD64)

tcc = Group("tcc", kit)
for p in sorted((G / "tcc").iterdir()):
    tcc.diff(p, "tcc-0.9.27/")
for path, name in [("tcctools.c", "remove-fileopen"), ("tcctools.c", "addback-fileopen"),
                   ("tccelf.c", "check-reloc-null")]:
    tcc.replace("tcc-0.9.27/" + path, (G / "tcc-simple" / f"{name}.before").read_bytes(),
                (G / "tcc-simple" / f"{name}.after").read_bytes())
for p in sorted((ROOT / "patches/ladder/tcc").glob("*.diff")):
    tcc.diff(p, "tcc-0.9.27/")                 # our own fixes, after gcc64's
tcc.done()

bridge = Group("bridge", kit)
bridge.diff(G / "libc64/01-bridge.diff", "libc64/")
bridge.done()

musl = Group("musl", untar(MUSL, "musl-1.1.24/"))
for p in sorted((G / "musl-1.1.24").iterdir()):
    if not p.name.startswith("05-"):
        musl.diff(p)
musl.done()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
if args.check:
    present = {p.name: p.read_bytes() for p in OUT.iterdir() if p.is_file()}
    if present != outputs:
        raise SystemExit("gcc64 exact fixtures differ; rerun tools/prepare-gcc64-exact.py")
    print(f"PASS: {len(outputs)} gcc64 exact fixture/manifest files match")
else:
    OUT.mkdir(exist_ok=True)
    for old in OUT.iterdir():
        if old.is_file() and old.name not in outputs:
            old.unlink()
    for name, data in outputs.items():
        (OUT / name).write_bytes(data)
    print(f"Wrote {len(outputs)} gcc64 exact fixture/manifest files")
