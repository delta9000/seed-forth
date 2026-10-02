#!/usr/bin/env python3
"""Audit remaining replay fixtures against pinned upstream build rules.

The required archive directory contains the ten ladder/PACKAGES inputs.
Outputs a JSON provenance inventory, without configuring or building any
package.  --summary prints counts instead.  This is a host-side audit,
not a source generator used by the bootstrap.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tarfile


ROOT = Path(__file__).resolve().parents[2]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inventory(distfiles):
    result = []
    for line in (ROOT / "ladder/PACKAGES").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        name, filename, expected, _ = line.split()
        archive = distfiles / filename
        if not archive.is_file() or sha(archive.read_bytes()) != expected:
            raise SystemExit("missing or unpinned archive: " + str(archive))
        fixtures = ROOT / "ladder" / name / "fixtures"
        rules = {}
        with tarfile.open(archive) as tar:
            for member in tar:
                if not member.isfile() or not member.name.endswith("/Makefile.in"):
                    continue
                top, makefile = member.name.split("/", 1)
                if top != name:
                    raise SystemExit("unexpected archive root: " + top)
                directory = Path(makefile).parent
                lines = tar.extractfile(member).read().decode().splitlines()
                for index, text in enumerate(lines):
                    clean = re.sub(r"^(?:@[A-Za-z0-9_]+@)+", "", text)
                    if not clean or clean[0].isspace() or ":" not in clean:
                        continue
                    targets, dependencies = clean.split(":", 1)
                    if "$" in targets or "=" in targets:
                        continue
                    for target in targets.split():
                        relative = str(directory / target)
                        if not (fixtures / relative).is_file():
                            continue
                        commands = []
                        for following in lines[index + 1:]:
                            if not re.sub(r"^(?:@[A-Za-z0-9_]+@)+", "", following).startswith(("\t", " ")):
                                break
                            commands.append(following)
                        rules.setdefault(relative, []).append({
                            "makefile": makefile,
                            "line": index + 1,
                            "dependencies": dependencies.strip(),
                            "commands": commands,
                        })
        entries = []
        for path in sorted(fixtures.rglob("*")):
            if not path.is_file():
                continue
            relative = str(path.relative_to(fixtures))
            if relative not in rules:
                raise SystemExit("no upstream generation rule: " + name + "/" + relative)
            data = path.read_bytes()
            entries.append({"fixture": relative, "bytes": len(data),
                            "sha256": sha(data), "rules": rules[relative]})
        result.append({"package": name, "archive": filename,
                       "archive_sha256": expected, "fixtures": entries})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--distfiles", type=Path, required=True)
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()
    result = inventory(args.distfiles)
    if not args.summary:
        print(json.dumps(result, indent=2))
        return
    files = size = 0
    for package in result:
        count = len(package["fixtures"])
        total = sum(f["bytes"] for f in package["fixtures"])
        files += count
        size += total
        print(f'{package["package"]}: {count} fixtures, {total} bytes')
    print(f"TOTAL: {files} fixtures, {size} bytes; every upstream rule found")


if __name__ == "__main__":
    main()
