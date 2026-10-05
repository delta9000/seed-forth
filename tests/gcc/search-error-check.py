#!/usr/bin/env python3
"""Runtime bsearch and strerror match host libc on the same source.

tests/gcc/search-error.c is compiled once by the production Forth driver
with the source-built runtime and once by host GCC with host libc, the
oracle.  Both executables must exit 0 and print identical output.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/gcc/search-error.c"


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, timeout=300, **kwargs)
    if result.returncode:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


def main():
    (ROOT / "build-out").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="search-error-", dir=ROOT / "build-out"))
    forth = work / "search-error-forth"
    run([sys.executable, ROOT / "tools/gcc-direct-cc.py", SOURCE, "-o", forth])
    expected = None
    for optimization in ("-O0", "-O2"):
        host = work / ("search-error-host" + optimization)
        run(["gcc", "-std=c90", "-Wall", "-Wextra", "-Werror", optimization,
             "-fno-builtin", "-U_FORTIFY_SOURCE", SOURCE, "-o", host])
        output = run([host]).stdout
        if expected is not None and output != expected:
            raise SystemExit("host oracle disagrees with itself across optimization levels")
        expected = output
    actual = run([forth]).stdout
    if actual != expected:
        for number, (a, e) in enumerate(zip(actual.splitlines(), expected.splitlines()), 1):
            if a != e:
                raise SystemExit(f"line {number}: forth {a!r} != host {e!r}")
        raise SystemExit("output lengths differ")
    lines = expected.count(b"\n")
    print(f"PASS: runtime bsearch/strerror match host libc on {lines} lines", flush=True)
    print("Oracle only: host GCC and host libc build the reference executable.")
    print(work)


if __name__ == "__main__":
    main()
