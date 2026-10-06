#!/usr/bin/env python3
"""Signed left shifts in integer constant expressions, host GCC as oracle.

GCC folds `-1L << 3` and coreutils' TYPE_MINIMUM, `~(t)0 << (bits - 1)`,
as two's complement even though C leaves a negative or overflowing signed
left shift undefined. shift-constants.c uses such shifts in static
initializers, case labels, an array bound and enumerators; the Forth build
must print what the host GCC builds print. Counts that are negative or at
least the promoted width keep error 241.
"""
from pathlib import Path
import hashlib
import json
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/gcc/shift-constants.c"
DRIVER = ROOT / "tools/gcc-direct-cc.py"
LIMIT = 1024 ** 3


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(command, expected=0):
    command = [str(part) for part in command]
    result = subprocess.run(command, capture_output=True, timeout=300, preexec_fn=limits)
    if result.returncode != expected:
        raise SystemExit(f"{command}: exit {result.returncode}, expected {expected}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


(ROOT / "build-out").mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix="shift-constants-", dir=ROOT / "build-out"))
run([sys.executable, DRIVER, SOURCE, "-o", work / "forth"])
actual = run([work / "forth"]).stdout
if b"x -8\n" not in actual or b"case minus-four int-minimum minus-forty-eight other\n" not in actual:
    raise SystemExit("Forth program did not complete:\n" + actual.decode(errors="replace"))
for optimization in ("-O0", "-O2"):
    host = work / ("host" + optimization)
    run(["gcc", "-std=gnu89", "-w", optimization, SOURCE, "-o", host])
    expected = run([host]).stdout
    if actual != expected:
        raise SystemExit(f"{optimization}: output differs\nforth:\n{actual.decode()}\nhost:\n{expected.decode()}")
rejects = {
    "count-width": (241, "static int x = -1 << 32;\n"),
    "count-long-width": (241, "static long x = -1L << 64;\n"),
    "count-negative": (241, "int f(int v) { switch (v) { case 1 << -1: return 1; } return 0; }\n"),
    "count-promoted": (241, "enum { E = (char) -1 << 32 };\n"),
    "signed-overflow": (242, "static int x = 2147483647 + 1;\n"),
}
for name, (code, text) in rejects.items():
    source = work / (name + ".c")
    source.write_text(text)
    result = run([sys.executable, DRIVER, "-c", source, "-o", work / (name + ".o")], expected=code)
    if f"error {code}".encode() not in result.stderr or (work / (name + ".o")).exists():
        raise SystemExit(f"{name}: missing error {code} or output published: {result.stderr!r}")
report = {"lines": actual.count(b"\n"), "host_oracles": ["-O0", "-O2"], "rejects": sorted(rejects),
          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in (SOURCE, Path(__file__), ROOT / "125-cc-consteval.fth")},
          "forth_sha256": hashlib.sha256((work / "forth").read_bytes()).hexdigest()}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: constant signed left shifts match host GCC on {report['lines']} lines; "
      f"{len(rejects)} rejections", flush=True)
print(work / "report.json")
