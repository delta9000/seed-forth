#!/usr/bin/env python3
"""Retain a source snapshot; build and execute qsort entirely through Forth."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASE = ["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, timeout=120, **kwargs)
    if result.returncode or result.stdout or result.stderr:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


def path_word(name, path):
    return "create " + name + "\n" + "".join(
        f"[lit] {byte} c,\n" for byte in os.fsencode(path) + b"\0")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, help="retain production evidence here")
    args = parser.parse_args()
    if not (ROOT / "seed-forth").is_file():
        subprocess.run([ROOT / "build.sh"], check=True)
    (ROOT / "build-out").mkdir(exist_ok=True)
    work = args.work.resolve() if args.work else Path(tempfile.mkdtemp(prefix="sort-production-", dir=ROOT / "build-out"))
    work.mkdir(parents=True, exist_ok=True)
    frozen = work / "source"
    inputs = sorted(set([ROOT / "seed-forth", ROOT / "010-lib.fth",
                         ROOT / "tests/gcc/sysv-object-compile.sh",
                         ROOT / "runtime/gcc-seed/sort.c", ROOT / "runtime/gcc-seed/qsort.c",
                         ROOT / "runtime/gcc-seed/memory.c"]
                        + list(ROOT.glob("[0-9][0-9][0-9]-cc-*.fth"))
                        + list((ROOT / "runtime/gcc-seed/include").rglob("*.h"))
                        + list((ROOT / "tests/gcc").glob("sort-*"))))
    hashes = {str(p.relative_to(ROOT)): sha(p) for p in inputs if p.is_file()}
    for name, expected in hashes.items():
        target = frozen / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
        if sha(target) != expected:
            raise SystemExit("input changed while snapshotting: " + name)
    if any(sha(ROOT / name) != expected for name, expected in hashes.items()):
        raise SystemExit("source inputs changed during snapshot; retry")

    def forth(modules, driver):
        source = b"\n".join((frozen / name).read_bytes() for name in modules)
        run([frozen / "seed-forth"], input=source + b"\n" + driver.encode())

    objects = []
    for source in ("runtime/gcc-seed/sort.c", "runtime/gcc-seed/qsort.c", "runtime/gcc-seed/memory.c",
                   "tests/gcc/sort-production.c"):
        obj = work / (Path(source).stem + ".o")
        run([frozen / "tests/gcc/sysv-object-compile.sh", frozen / source, obj,
             frozen / "runtime/gcc-seed/include"])
        objects.append(obj)
    driver = ""
    for name, builder in (("syscall", "cc-sysrt-object"),
                          ("start", "cc-sysrt-start-object")):
        obj = work / (name + ".o")
        driver += path_word(name + "-output", obj)
        driver += f"{builder} {name}-output cc-obj-write\n"
        objects.append(obj)
    forth(BASE + ["081-cc-object.fth", "122-cc-sysv-runtime.fth"], driver + "bye\n")
    executable = work / "sort-production"
    driver = "lnk-init\n"
    for index, obj in enumerate(objects):
        driver += path_word(f"object-{index}", obj)
        driver += f"object-{index} lnk-add-object\n"
    driver += "create entry-name s, _start\nentry-name [lit] 6 lnk-entry\n"
    driver += path_word("program", executable) + "program lnk-link bye\n"
    forth(BASE + ["140-cc-link.fth"], driver)
    run([executable])
    assert all(sha(frozen / name) == expected for name, expected in hashes.items())
    report = {"proof": "Forth-compiled qsort and test; Forth ABI objects; Forth linker",
              "host_compiler": False, "host_assembler": False,
              "host_linker": False, "host_libc": False,
              "cases": ["all permutations through 8 elements", "0/1 and 4096 elements",
                        "ascending/reverse/equal/organ-pipe/alternating/random/sawtooth",
                        "full-width comparator results", "byte records of widths 1..33 and 257",
                        "offsets 1..8 and complete byte-permutation oracle", "mode pointers",
                        "nested callback sorting three levels", "equal-key runs left in input order", "guard pages at both edges"],
              "artifacts": str(work), "source_sha256": hashes,
              "artifact_sha256": {p.name: sha(p) for p in objects + [executable]}}
    (work / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("PASS: source-built qsort production reconstruction and semantic guards")
    print(work / "report.json")


if __name__ == "__main__":
    main()
