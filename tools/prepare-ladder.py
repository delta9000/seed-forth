#!/usr/bin/env python3
"""Authoring/checking tool: write stage 9 of tools/ladder.recipe from
ladder/PACKAGES and each package's ladder/NAME/{recipe,HASHES}.

Every package: pin its tarball, unpack it into a fresh directory, run its
captured recipe in a child runner (with CC, P, L, SRC and B set), then pin
each installed file against the host capture's hash.  --check verifies.
"""
import argparse, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARK = "# ---- stage 9:"
ap = argparse.ArgumentParser(); ap.add_argument("--check", action="store_true")
args = ap.parse_args()
out = [MARK + " the first tools, each replayed from a host capture ----",
       "# ladder/NAME/recipe was written by tools/capture-build.py; its fixtures are",
       "# the files the host's configure and shell wrote that the build reads.",
       "set TC ${G}/tc/bin/tcc", "set U ${W}/usr", "mkdir ${U}", "mkdir ${U}/bin",
       "mkdir ${W}/src"]
for line in (ROOT / "ladder/PACKAGES").read_text().splitlines():
    if not line.strip() or line.startswith("#"):
        continue
    name, tarball, sha, how = line.split()
    d = ROOT / "ladder" / name
    top = name                                   # tarballs unpack to NAME/
    S = "${W}/src/" + name
    out += [f"# {name}", f"pin ${{D}}/{tarball} {sha}", f"mkdir {S}", f"cd {S}"]
    if how == "bintools":
        out.append(f"run 0 - {S}.tar {S}.err ${{K}}/bintools ungz --file ${{D}}/{tarball} --output {S}.tar")
        out[-1] = f"run 0 - {S}.out {S}.err ${{K}}/bintools ungz --file ${{D}}/{tarball} --output {S}.tar"
    elif how == "gzip":
        out.append(f"run 0 - {S}.tar {S}.err ${{U}}/bin/gzip -dc ${{D}}/{tarball}")
    else:
        raise SystemExit(f"unknown unpack method {how}")
    out += [f"run 0 - {S}.out {S}.err ${{K}}/bintools untar {S}.tar",
            f"unlink {S}.tar",
            f"cd {S}/{top}",
            f'text {S}.head "set CC ${{TC}}\\nset T ${{G}}/tools\\nset P ${{U}}\\nset L ${{W}}/src\\nset SRC ${{ROOT}}/ladder/{name}\\nset B {S}/{top}\\n"',
            f"cat {S}.recipe {S}.head ${{ROOT}}/ladder/{name}/recipe",
            f"run 0 - {S}.log {S}.err ${{ROOT}}/build-out/amd64-runner --recipe {S}.recipe"]
    rec = (d / "recipe").read_text()
    for h in (d / "HASHES").read_text().splitlines():
        digest, srcfile = h.split()
        m = re.search(rf"^copy {re.escape(srcfile)} \$\{{P\}}/(\S+)$", rec, re.M)
        dst = m.group(1)
        if dst.startswith("bin/"):
            out.append(f"chmod ${{U}}/{dst}")
        out.append(f"artifact ${{U}}/{dst} {digest}")
    out.append(f'say "ladder: {name}"')
p = ROOT / "tools/ladder.recipe"
s = p.read_text()
head = s[:s.index(MARK)] if MARK in s else s
new = head + "\n".join(out) + "\n"
if args.check:
    if p.read_text() != new:
        raise SystemExit("tools/ladder.recipe stage 9 is stale")
else:
    p.write_text(new)
print("ladder stage 9:", ", ".join(l.split()[0] for l in (ROOT / "ladder/PACKAGES").read_text().splitlines() if l.strip() and not l.startswith("#")))
