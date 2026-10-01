#!/usr/bin/env python3
"""Authoring/checking tool, never run by the bootstrap recipe.

Derive committed exact-match fixtures and hashes from the pinned sources and
reviewable upstream/local patches. --check verifies without changing files.
"""
import argparse
import hashlib
from pathlib import Path
import re
import tarfile

ROOT = Path(__file__).resolve().parents[1]
PNUT = ROOT / "vendor/pnut"
PATCHES = ROOT / "patches/amd64"
OUT = PATCHES / "exact"
sha = lambda data: hashlib.sha256(data).hexdigest()
files = {}
outputs = {}
with tarfile.open(PNUT / "kit/tcc-0.9.27.tar.gz") as archive:
    for member in archive.getmembers():
        if member.isfile():
            files[member.name] = archive.extractfile(member).read()
for path in (PNUT / "portable_libc").rglob("*"):
    if path.is_file():
        files["libc64/" + str(path.relative_to(PNUT / "portable_libc"))] = path.read_bytes()
files["pnut.c"] = (PNUT / "pnut.c").read_bytes()


def replace(rows, source, target, stem, before, after):
    original = files[source]
    first = original.find(before)
    if not before or first < 0 or original.find(before, first + 1) >= 0:
        raise ValueError(f"{stem}: old hunk must be nonempty and unique in {source}")
    changed = original[:first] + after + original[first + len(before):]
    outputs[stem + ".before"] = before
    outputs[stem + ".after"] = after
    rows.append(f"replace {source} {target} {stem}.before {stem}.after {sha(original)} {sha(changed)}\n")
    files[target] = changed


kit_rows = []
kit = ["tccpp.c:array_sizeof", "tcc.h:attribute", "tcc.h:bitfields",
       "tccgen.c:float_negation", "tccgen.c:float_zero_division_check",
       "tccgen.c:long_double_codegen", "tccpp.c:scientific-notation-parser",
       "libtcc.c:sscanf_TCC_VERSION"]
for number, item in enumerate(kit, 1):
    target, name = item.split(":")
    path = PNUT / "kit/tcc-patches/0.9.27"
    target = "tcc-0.9.27/" + target
    replace(kit_rows, target, target, f"kit-{number:02d}",
            (path / (name + ".before")).read_bytes(),
            (path / (name + ".after")).read_bytes())
outputs["kit.manifest"] = "".join(kit_rows).encode()

for group, prefix in [("tcc", "tcc-0.9.27/"), ("libc", "libc64/"), ("pnut", "")]:
    rows = []
    for patch in sorted((PATCHES / group).glob("*.diff")):
        lines = patch.read_bytes().splitlines(keepends=True)
        index = 0
        hunk = 0
        new_file = False
        target = None
        while index < len(lines):
            line = lines[index]
            if line.startswith(b"--- "):
                new_file = line.strip() == b"--- /dev/null"
            elif line.startswith(b"+++ "):
                target = prefix + line[4:].strip().decode().removeprefix("b/")
            elif line.startswith(b"@@ "):
                match = re.fullmatch(rb"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@[^\n]*\n", line)
                if match is None or target is None:
                    raise ValueError(f"unsupported hunk: {patch}: {line!r}")
                old_count = int(match[2] or b"1")
                new_count = int(match[4] or b"1")
                before, after = [], []
                index += 1
                while index < len(lines) and lines[index][:1] in (b" ", b"-", b"+"):
                    row = lines[index]
                    if row.startswith((b"--- ", b"+++ ")):
                        break
                    if row[:1] in (b" ", b"-"):
                        before.append(row[1:])
                    if row[:1] in (b" ", b"+"):
                        after.append(row[1:])
                    index += 1
                if len(before) != old_count or len(after) != new_count:
                    raise ValueError(f"hunk count mismatch: {patch}")
                if index < len(lines) and lines[index].startswith(b"\\"):
                    raise ValueError("no-newline annotations not supported by authoring tool")
                hunk += 1
                stem = f"{group}-{patch.name[:2]}-{hunk}"
                before, after = b"".join(before), b"".join(after)
                if new_file:
                    if target in files or before:
                        raise ValueError(f"add target exists or has old content: {target}")
                    outputs[stem + ".file"] = after
                    files[target] = after
                    rows.append(f"copy {stem}.file {target} - - {sha(after)} {sha(after)}\n")
                else:
                    source = "pnut.c" if group == "pnut" else target
                    if group == "pnut":
                        target = "pnut-for-tcc.c"
                    replace(rows, source, target, stem, before, after)
                continue
            index += 1
    outputs[group + ".manifest"] = "".join(rows).encode()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
if args.check:
    present = {p.name: p.read_bytes() for p in OUT.iterdir() if p.is_file()}
    if present != outputs:
        raise SystemExit("exact fixtures differ; rerun tools/prepare-amd64-exact-patches.py")
    print(f"PASS: {len(outputs)} exact fixture/manifest files match pinned inputs and diffs")
else:
    OUT.mkdir(exist_ok=True)
    for old in OUT.iterdir():
        if old.is_file() and old.name not in outputs:
            old.unlink()
    for name, data in outputs.items():
        (OUT / name).write_bytes(data)
    print(f"Wrote {len(outputs)} exact fixture/manifest files")
