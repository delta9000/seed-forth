#!/usr/bin/env python3
"""Grouped direct declarators: (*(name[N][M]))(...) as in binutils nm.c.

The Forth-built program and host GCC/glibc C90 builds (-O0/-O2, the
independent oracle) must print identical bytes. Shapes outside the bounded
declarator profile must still fail with their documented codes.
"""
from pathlib import Path
import hashlib
import json
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/gcc/grouped-declarator.c"
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
work = Path(tempfile.mkdtemp(prefix="grouped-declarator-", dir=ROOT / "build-out"))
run([sys.executable, DRIVER, SOURCE, "-o", work / "forth"])
actual = run([work / "forth"]).stdout
if b"sorters[1][1] 1001\n" not in actual or not actual.endswith(b"apply 16 64\n"):
    raise SystemExit("Forth program did not complete:\n" + actual.decode(errors="replace"))
for optimization in ("-O0", "-O2"):
    host = work / ("host" + optimization)
    run(["gcc", "-std=c90", "-pedantic-errors", "-Wall", "-Wextra", "-Werror", optimization,
         SOURCE, "-o", host])
    expected = run([host]).stdout
    if actual != expected:
        raise SystemExit(f"{optimization}: output differs\nforth:\n{actual.decode()}\nhost:\n{expected.decode()}")
# Outside the profile: a pointer group nested in a group (238), a typedef
# name where a grouped declarator name is required (203), and array suffixes
# both inside and after the inner group (238).
rejects = {
    "nested-pointer-group": (238, "int (*(*p))(void);\n"),
    "typedef-name": (203, "typedef int T;\nint (*(T))(void);\n"),
    "split-suffixes": (238, "int (*(s[2])[3])(void);\n"),
}
for name, (code, text) in rejects.items():
    source = work / (name + ".c")
    source.write_text(text)
    result = run([sys.executable, DRIVER, "-c", source, "-o", work / (name + ".o")], expected=code)
    if f"error {code}".encode() not in result.stderr:
        raise SystemExit(f"{name}: missing error {code}: {result.stderr!r}")
report = {"lines": actual.count(b"\n"), "host_oracles": ["-O0", "-O2"], "rejects": sorted(rejects),
          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in (SOURCE, Path(__file__), ROOT / "115-cc-native.fth")},
          "forth_sha256": hashlib.sha256((work / "forth").read_bytes()).hexdigest()}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: grouped declarators match host GCC on {report['lines']} lines; "
      f"{len(rejects)} rejections", flush=True)
print(work / "report.json")
