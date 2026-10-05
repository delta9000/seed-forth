#!/usr/bin/env python3
"""Runtime strtol matches host libc on the same source (host GCC oracle only)."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/gcc/strtol-check.c"


def run(command):
    result = subprocess.run(command, capture_output=True, timeout=300)
    if result.returncode:
        raise SystemExit(f"{command}: exit {result.returncode}\n" + result.stderr.decode(errors="replace"))
    return result.stdout


(ROOT / "build-out").mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix="strtol-", dir=ROOT / "build-out"))
run([sys.executable, ROOT / "tools/gcc-direct-cc.py", SOURCE, "-o", work / "forth"])
actual = run([work / "forth"])
for optimization in ("-O0", "-O2"):
    host = work / ("host" + optimization)
    run(["gcc", "-std=c90", "-Wall", "-Wextra", "-Werror", optimization, "-fno-builtin",
         "-U_FORTIFY_SOURCE", SOURCE, "-o", host])
    expected = run([host])
    if actual != expected:
        for n, (a, e) in enumerate(zip(actual.splitlines(), expected.splitlines()), 1):
            if a != e:
                raise SystemExit(f"line {n}: forth {a!r} != host {e!r}")
        raise SystemExit("output lengths differ")
lines = actual.count(b"\n")
print(f"PASS: runtime strtol matches host libc on {lines} lines", flush=True)
print(work)
