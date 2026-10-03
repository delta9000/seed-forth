#!/usr/bin/env python3
"""Build the production syscall object in Forth; use host C only as an oracle."""
from pathlib import Path
import json
import hashlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MODULES = ["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth",
           "081-cc-object.fth", "122-cc-sysv-runtime.fth"]


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, check=False, **kwargs)
    if result.returncode:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


def main():
    cc = shutil.which("gcc")
    if not cc:
        print("SKIP: gcc is required for the independent ABI oracle")
        raise SystemExit(77)
    if not (ROOT / "seed-forth").is_file():
        run([str(ROOT / "build.sh")])
    work_parent = ROOT / "build-out"
    work_parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="syscall-check.", dir=work_parent) as t:
        work = Path(t)
        obj = work / "syscall.o"
        # Build pathname bytes explicitly, without Forth token/path restrictions.
        path = "create syscall-output\n" + "".join(
            f"[lit] {b} c,\n" for b in bytes(obj) + b"\0")
        driver = path + "cc-sysrt-object syscall-output cc-obj-write bye\n"
        source = b"".join((ROOT / p).read_bytes() for p in MODULES) + driver.encode()
        result = run([str(ROOT / "seed-forth")], input=source)
        if result.stdout or result.stderr:
            raise SystemExit("unexpected Forth compiler output: " + repr(result))
        for optimization in ("-O0", "-O2"):
            exe = work / ("oracle" + optimization[1:])
            run([cc, "-std=c99", "-Wall", "-Wextra", "-Werror", optimization,
                 "-fno-pie", "-no-pie", "-Wl,-z,noexecstack",
                 str(ROOT / "tests/gcc/syscall-oracle.c"), str(obj), "-o", str(exe)])
            print(run([str(exe)]).stdout.decode().strip(), optimization)
        print(json.dumps({"object_sha256": hashlib.sha256(obj.read_bytes()).hexdigest(),
                          "bytes": obj.stat().st_size,
                          "production_inputs": MODULES}, sort_keys=True))


if __name__ == "__main__":
    main()
