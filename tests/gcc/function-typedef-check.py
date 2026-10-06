#!/usr/bin/env python3
"""Typedefs of function types: typedef int Function (); Function *p;

The Forth-built program and host GCC/glibc C90 builds (-O0/-O2, the
independent oracle) must print identical bytes, including a char * result
above 4 GiB through a table of CPFunction pointers and a getenv result
through a block-scope `extern CPFunction getenv;`. Forbidden shapes must
fail with their documented codes.
"""
from pathlib import Path
import hashlib
import json
import os
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/gcc/function-typedef.c"
DRIVER = ROOT / "tools/gcc-direct-cc.py"
LIMIT = 1024 ** 3
ENV = dict(os.environ, FUNCTION_TYPEDEF_VALUE="typedef-value")


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(command, expected=0):
    command = [str(part) for part in command]
    result = subprocess.run(command, capture_output=True, timeout=300, preexec_fn=limits, env=ENV)
    if result.returncode != expected:
        raise SystemExit(f"{command}: exit {result.returncode}, expected {expected}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


(ROOT / "build-out").mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix="function-typedef-", dir=ROOT / "build-out"))
run([sys.executable, DRIVER, SOURCE, "-o", work / "forth"])
actual = run([work / "forth"]).stdout
if (b"getenv typedef-value above-4GiB 1\n" not in actual
        or b"table buffer 123456789a0 1\n" not in actual or not actual.endswith(b"failures 0\n")):
    raise SystemExit("Forth program did not complete:\n" + actual.decode(errors="replace"))
for optimization in ("-O0", "-O2"):
    host = work / ("host" + optimization)
    run(["gcc", "-std=c90", "-pedantic-errors", "-Wall", "-Wextra", "-Werror", optimization,
         SOURCE, "-o", host])
    expected = run([host]).stdout
    if actual != expected:
        raise SystemExit(f"{optimization}: output differs\nforth:\n{actual.decode()}\nhost:\n{expected.decode()}")
# C forbids arrays and members of function type, functions returning
# functions and a definition through a function typedef (238); a typedef
# has no identifier list and a block-scope function no static (233); and
# every declaration of one function must agree (237).
rejects = {
    "array": (238, "typedef int F(); F a[2];\n"),
    "member": (238, "typedef int F(); struct s { F f; };\n"),
    "returns-function": (238, "typedef int F(); F f(void);\n"),
    "definition": (238, "typedef int F(void); F g { return 1; }\n"),
    "identifier-list": (233, "typedef int K(a, b);\n"),
    "block-static": (233, "typedef int F(); int h(void){ static F g; return 0; }\n"),
    "conflict": (237, "typedef int F(); F g; long g(void){ return 0; }\n"),
}
for name, (code, text) in rejects.items():
    source = work / (name + ".c")
    source.write_text(text)
    result = run([sys.executable, DRIVER, "-c", source, "-o", work / (name + ".o")], expected=code)
    if f"error {code}".encode() not in result.stderr:
        raise SystemExit(f"{name}: missing error {code}: {result.stderr!r}")
report = {"lines": actual.count(b"\n"), "host_oracles": ["-O0", "-O2"], "rejects": sorted(rejects),
          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in (SOURCE, Path(__file__), ROOT / "121-cc-sysv.fth")},
          "forth_sha256": hashlib.sha256((work / "forth").read_bytes()).hexdigest()}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: function typedefs match host GCC on {report['lines']} lines; "
      f"{len(rejects)} rejections", flush=True)
print(work / "report.json")
