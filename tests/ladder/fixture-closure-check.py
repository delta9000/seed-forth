#!/usr/bin/env python3
"""Check the first three removed host-capture fixtures.

Without options this checks source/recipe closure only.  --distfiles also
checks the original archive inputs.  --cc and --runner together replay the
complete Bash and gawk recipes in a private directory, requiring all old
generated-source and executable hashes to remain unchanged.  The caller
supplies the seed-derived tcc-musl and runner; this host-side test harness
is not itself part of the bootstrap.
"""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[2]
REMOVED = {
    "bash-5.2.37": {
        "signames.h": "5583c0c2fdaed365c00a1025bb1b900f8cb8a9884bab55c43dc370a98390406f",
    },
    "gawk-5.3.1": {
        "awklib/grcat.c": "dd5d3f25c95387a45413d2d14c5d6c4f348aef2ccb9f803df14d566e64e17f30",
        "awklib/pwcat.c": "c3aedb25f3bbd6e9cfe0c84fe4d8d00866080ad7a2ce117a30a576eb6ece50ea",
    },
}


def require(condition, message):
    if not condition:
        raise SystemExit("fixture-closure: FAIL: " + message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def quoted(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def source_checks():
    for name, files in REMOVED.items():
        recipe = (ROOT / "ladder" / name / "recipe").read_text()
        for path in files:
            require(not (ROOT / "ladder" / name / "fixtures" / path).exists(),
                    f"removed fixture returned: {name}/{path}")
            require(f"${{SRC}}/fixtures/{path}" not in recipe,
                    f"recipe still imports {name}/{path}")
    bash = (ROOT / "ladder/bash-5.2.37/recipe").read_text().splitlines()
    generate = next(i for i, s in enumerate(bash) if s.endswith(" ./mksignames lsignames.h"))
    copy = bash.index("copy lsignames.h signames.h")
    consume = next(i for i, s in enumerate(bash) if s.endswith(" -c trap.c"))
    require(generate < copy < consume, "Bash signal table generation is out of order")
    gawk = (ROOT / "ladder/gawk-5.3.1/recipe").read_text()
    for file in ("grcat.c", "pwcat.c"):
        require(f"copy awklib/eg/lib/{file} awklib/{file}\n" in gawk,
                "gawk must use its original archive example: " + file)
    # These packagers stage ladder recursively.  Absence, rather than simply
    # non-use by a recipe, is what excludes the old files from initial input.
    for name, files in REMOVED.items():
        for path in files:
            relative = f"ladder/{name}/fixtures/{path}"
            for script in ("tools/tcc_inputs.py", "k0/mkfs.py", "k1/mkdisk.py"):
                require(relative not in (ROOT / script).read_text(),
                        script + " explicitly restores a removed fixture")
    print("fixture-closure: PASS: removed inputs absent; generation precedes consumption")


def archive_checks(distfiles):
    packages = {}
    for line in (ROOT / "ladder/PACKAGES").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            name, archive, sha, _ = line.split()
            packages[name] = (archive, sha)
    for name in REMOVED:
        archive, sha = packages[name]
        path = distfiles / archive
        require(path.is_file(), "missing pinned archive: " + str(path))
        require(digest(path) == sha, "archive hash mismatch: " + archive)
        with tarfile.open(path) as tar:
            if name.startswith("gawk"):
                for file, expected in REMOVED[name].items():
                    original = name + "/awklib/eg/lib/" + Path(file).name
                    data = tar.extractfile(original).read()
                    require(hashlib.sha256(data).hexdigest() == expected,
                            "upstream example differs: " + original)
            else:
                for original in ("support/mksignames.c", "support/signames.c"):
                    require(tar.getmember(name + "/" + original).isfile(),
                            "missing upstream signal generator: " + original)
    print("fixture-closure: PASS: pinned archives and original gawk sources verified")
    return packages


def replay(distfiles, packages, cc, runner, work):
    for name, files in REMOVED.items():
        package_work = work / name
        package_work.mkdir()
        with tarfile.open(distfiles / packages[name][0]) as tar:
            tar.extractall(package_work, filter="data")
        source = package_work / name
        logs = package_work / "logs"
        prefix = package_work / "install"
        logs.mkdir()
        (prefix / "bin").mkdir(parents=True)
        variables = {
            "CC": cc, "B": source, "SRC": ROOT / "ladder" / name,
            "P": prefix, "L": logs,
        }
        script = package_work / "replay.recipe"
        head = "".join(f"set {key} {quoted(value)}\n" for key, value in variables.items())
        head += "cd " + quoted(source) + "\n"
        script.write_text(head + (ROOT / "ladder" / name / "recipe").read_text())
        with (logs / "runner.log").open("wb") as output:
            result = subprocess.run([str(runner), "--recipe", str(script)], cwd=ROOT,
                                    stdout=output, stderr=subprocess.STDOUT, timeout=600)
        require(result.returncode == 0, f"{name} replay failed; see {logs}")
        for path, expected in files.items():
            require(digest(source / path) == expected,
                    f"regenerated source hash differs: {name}/{path}")
        for line in (ROOT / "ladder" / name / "HASHES").read_text().splitlines():
            expected, path = line.split()
            require(digest(source / path) == expected,
                    "original executable pin changed: " + name + "/" + path)
            require(digest(prefix / "bin" / Path(path).name) == expected,
                    "installed executable differs: " + name + "/" + path)
        print(f"fixture-closure: PASS: {name} sources and full executable pins unchanged")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--distfiles", type=Path)
    parser.add_argument("--cc", type=Path, help="seed-derived tcc-musl executable")
    parser.add_argument("--runner", type=Path, help="seed-derived recipe runner")
    parser.add_argument("--work", type=Path, help="new directory to keep replay evidence")
    args = parser.parse_args()
    require(bool(args.cc) == bool(args.runner), "--cc and --runner must be supplied together")
    require(not args.cc or args.distfiles, "replay requires --distfiles")
    require(not args.work or args.cc, "--work requires replay")
    source_checks()
    if not args.distfiles:
        print("fixture-closure: archive/replay checks NOT RUN (provide --distfiles and tools)")
        return
    distfiles = args.distfiles.resolve()
    packages = archive_checks(distfiles)
    if not args.cc:
        print("fixture-closure: executable replay NOT RUN (provide --cc and --runner)")
        return
    cc, runner = args.cc.resolve(), args.runner.resolve()
    require(cc.is_file() and runner.is_file(), "supplied chain tools do not exist")
    if args.work:
        work = args.work.resolve()
        require(not work.exists(), "--work must name a new directory")
        work.mkdir(parents=True)
        replay(distfiles, packages, cc, runner, work)
    else:
        with tempfile.TemporaryDirectory(prefix="fixture-closure-") as directory:
            replay(distfiles, packages, cc, runner, Path(directory))


if __name__ == "__main__":
    main()
