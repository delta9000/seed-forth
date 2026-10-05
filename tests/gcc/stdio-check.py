#!/usr/bin/env python3
"""Forth-only stdio reconstruction; retain real-kernel and fault-test artifacts."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/gcc-seed"
BASE = ["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth"]


def run(command, expected=b"", expected_error=b"", **kwargs):
    result = subprocess.run(command, capture_output=True, timeout=60, **kwargs)
    if result.returncode or result.stdout != expected or result.stderr != expected_error:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + repr(result.stdout) + "\n" + repr(result.stderr))
    return result


def forth(modules, driver):
    source = b"\n".join((ROOT / name).read_bytes() for name in modules)
    run([ROOT / "seed-forth"], input=source + b"\n" + driver.encode())


def path_word(name, path):
    return "create " + name + "\n" + "".join(
        f"[lit] {byte} c,\n" for byte in bytes(path) + b"\0")


def link(objects, executable):
    driver = "lnk-init\n"
    for index, obj in enumerate(objects):
        driver += path_word(f"object-{index}", obj) + f"object-{index} lnk-add-object\n"
    driver += "create entry-name s, _start\nentry-name [lit] 6 lnk-entry\n"
    driver += path_word("program", executable) + "program lnk-link bye\n"
    forth(BASE + ["140-cc-link.fth"], driver)


def main():
    if not (ROOT / "seed-forth").is_file():
        subprocess.run([ROOT / "build.sh"], check=True)
    (ROOT / "build-out").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="stdio-production-", dir=ROOT / "build-out"))
    stdio = RUNTIME / "stdio.c"
    includes = [RUNTIME / "include"]
    sources = [RUNTIME / (name + ".c") for name in ("memory", "string", "alloc")]
    sources += [stdio, ROOT / "tests/gcc/stdio-production.c", ROOT / "tests/gcc/stdio-faults.c"]
    objects = {}
    for source in sources:
        obj = work / (source.stem + ".o")
        run([ROOT / "tests/gcc/sysv-object-compile.sh", source, obj, *includes])
        objects[source.stem] = obj
    driver = ""
    for name, builder in (("syscall", "cc-sysrt-object"),
                          ("errno", "cc-sysrt-errno-object"),
                          ("start", "cc-sysrt-start-object")):
        obj = work / (name + ".o")
        driver += path_word(name + "-output", obj)
        driver += f"{builder} {name}-output cc-obj-write\n"
        objects[name] = obj
    forth(BASE + ["081-cc-object.fth", "122-cc-sysv-runtime.fth"], driver + "bye\n")
    common = [objects[name] for name in ("memory", "string", "alloc", "stdio", "errno", "start")]
    production = work / "stdio-production"
    faults = work / "stdio-faults"
    link(common + [objects["stdio-production"], objects["syscall"]], production)
    link(common + [objects["stdio-faults"]], faults)
    run([production, work / "stream.bin"],
        expected=b"generator stdio\n#define PLUS_EXPR_CHECK(t)\tTREE_CHECK (t, PLUS_EXPR)\n!\n",
        expected_error=(b"diagnostic\nfixture: No such file or directory\n"
                        b"directory: Is a directory\nIs a directory\nIs a directory\n"
                        b"not-directory: Not a directory\nlong-name: File name too long\n"
                        b"symlink-loop: Too many levels of symbolic links\n"))
    if (work / "stream.bin").read_bytes() != b"abcdef\xff\nend:9":
        raise SystemExit("stream bytes differ")
    run([faults])
    inputs = sorted(set(sources + [ROOT / "seed-forth", ROOT / "010-lib.fth",
                      ROOT / "tests/gcc/sysv-object-compile.sh", Path(__file__).resolve()]
                     + list(ROOT.glob("[0-9][0-9][0-9]-cc-*.fth"))
                     + list((RUNTIME / "include").glob("*.h"))))
    report = {
        "proof": "Forth-compiled C, Forth ABI objects and linker; real Linux I/O",
        "host_compiler": False, "host_linker": False, "host_libc": False,
        "fault_test": "Separate Forth-compiled scripted syscall double for EINTR, short I/O and errors",
        "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
        "artifact_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in list(objects.values()) + [production, faults]},
    }
    (work / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("PASS: Forth-built stdio production and deterministic I/O-fault checks")
    print(work / "report.json")


if __name__ == "__main__":
    main()
