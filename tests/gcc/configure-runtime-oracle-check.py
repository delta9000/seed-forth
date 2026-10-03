#!/usr/bin/env python3
"""Optional independent host-header/libc oracle; never a production input."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def run(command):
    result = subprocess.run(command, capture_output=True, timeout=120)
    if result.returncode:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace"))
    return result.stdout


def main():
    cc = shutil.which("gcc")
    if not cc:
        raise SystemExit("host gcc is required only for the optional ABI oracle")
    if len(sys.argv) > 2:
        raise SystemExit("usage: configure-runtime-oracle-check.py [production-report.json]")
    report_path = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(
        run([sys.executable, ROOT / "tests/gcc/configure-runtime-check.py"]).decode().splitlines()[-1])
    report = json.loads(report_path.read_text())
    for name, value in report["source_sha256"].items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != value:
            raise SystemExit("production source identity is stale; rerun configure-runtime-check.py")
    work = report_path.parent
    expected = (work / "layout-output.txt").read_bytes()
    for optimization in ("-O0", "-O2"):
        executable = work / ("host-oracle" + optimization[1:])
        run([cc, "-std=c99", "-D_DEFAULT_SOURCE", "-Wall", "-Wextra", optimization,
             ROOT / "tests/gcc/configure-runtime-layout.c", "-o", executable])
        # No seed include path or seed object is passed to this host compiler.
        actual = run([executable, work / "sparse-file"])
        if actual != expected:
            raise SystemExit("host header/layout/libc disagreement:\n" + actual.decode())
        print("PASS: independent host header/layout/libc oracle", optimization)
    print("Oracle only: host GCC, host linker and host libc; no host bytes enter production artifacts.")


if __name__ == "__main__":
    main()
