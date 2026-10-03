#!/usr/bin/env python3
"""Reconstruct and execute the bounded C runtime with Forth, no host libc.

Python orchestrates and records hashes. Production target bytes are generated
only by the seed executing project Forth sources and the source C compiler.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/gcc-seed"
BASE = ["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth"]


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, timeout=60, **kwargs)
    if result.returncode or result.stdout or result.stderr:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


def forth(modules, driver):
    source = b"\n".join((ROOT / name).read_bytes() for name in modules)
    run([ROOT / "seed-forth"], input=source + b"\n" + driver.encode())


def path_word(name, path):
    return "create " + name + "\n" + "".join(
        f"[lit] {byte} c,\n" for byte in bytes(path) + b"\0")


def main():
    if not (ROOT / "seed-forth").is_file():
        subprocess.run([ROOT / "build.sh"], check=True)
    (ROOT / "build-out").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="runtime-production-", dir=ROOT / "build-out"))
    objects = []
    for name in ("memory", "string", "alloc", "test"):
        source = RUNTIME / (name + ".c") if name != "test" else ROOT / "tests/gcc/runtime-production.c"
        obj = work / (name + ".o")
        run([ROOT / "tests/gcc/sysv-object-compile.sh", source, obj, RUNTIME / "include"])
        objects.append(obj)
    driver = ""
    for name, builder in (("syscall", "cc-sysrt-object"),
                          ("errno", "cc-sysrt-errno-object"),
                          ("start", "cc-sysrt-start-object")):
        obj = work / (name + ".o")
        driver += path_word(name + "-output", obj)
        driver += f"{builder} {name}-output cc-obj-write\n"
        objects.append(obj)
    driver += "bye\n"
    forth(BASE + ["081-cc-object.fth", "122-cc-sysv-runtime.fth"], driver)
    executable = work / "runtime-production"
    driver = "lnk-init\n"
    for index, obj in enumerate(objects):
        driver += path_word(f"object-{index}", obj)
        driver += f"object-{index} lnk-add-object\n"
    driver += "create entry-name s, _start\nentry-name [lit] 6 lnk-entry\n"
    driver += path_word("executable-path", executable) + "executable-path lnk-link bye\n"
    forth(BASE + ["140-cc-link.fth"], driver)
    run([executable])
    source_inputs = sorted(set(
        [ROOT / "seed-forth", ROOT / "tests/gcc/sysv-object-compile.sh",
         ROOT / "tests/gcc/runtime-check.py", ROOT / "tests/gcc/runtime-production.c",
         ROOT / "010-lib.fth", ROOT / "140-cc-link.fth"]
        + [p for p in ROOT.glob("[0-9][0-9][0-9]-cc-*.fth")
           if p.name not in ("120-cc-main.fth", "140-cc-link.fth")]
        + list(RUNTIME.glob("*.c")) + list((RUNTIME / "include").glob("*.h"))))
    report = {"proof": "Forth-compiled C runtime, Forth-produced ABI objects, Forth linker",
              "host_compiler": False, "host_linker": False, "host_libc": False,
              "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in source_inputs},
              "artifact_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in objects + [executable]},
              "artifacts": str(work)}
    (work / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("PASS: source-built runtime production reconstruction")
    print(json.dumps({key: value for key, value in report.items() if key != "source_sha256"}, sort_keys=True))


if __name__ == "__main__":
    main()
