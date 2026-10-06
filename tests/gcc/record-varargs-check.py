#!/usr/bin/env python3
"""Records passed by value to unprototyped and variadic functions.

The caller and callee units are compiled by the Forth compiler and by host
GCC (-O0/-O2, an independent ABI oracle only). Every pairing must print the
same bytes: Forth caller + Forth callee (Forth-only link), Forth caller +
host callee, host caller + Forth callee, and host caller + host callee.
The units cover K&R and empty-parenthesis definitions, calls through
unprototyped declarations and pointers, variadic calls whose records go to
registers, to the stack when the remaining GP registers do not fit, and
after binary64 arguments, va_arg of every record class, va_copy, a variadic
MEMORY result and a named record before `...`. Records with floating
members keep error 232, as for prototyped calls.
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
TEST = ROOT / "tests/gcc"
CALLER = TEST / "record-varargs-caller.c"
CALLEE = TEST / "record-varargs-callee.c"
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
work = Path(tempfile.mkdtemp(prefix="record-varargs-", dir=ROOT / "build-out"))
forth_caller, forth_callee = work / "caller.o", work / "callee.o"
run([sys.executable, DRIVER, "-c", CALLER, "-o", forth_caller])
run([sys.executable, DRIVER, "-c", CALLEE, "-o", forth_callee])
run([sys.executable, DRIVER, forth_caller, forth_callee, "-o", work / "forth"])
actual = run([work / "forth"]).stdout
if not actual.startswith(b"knr ") or b"vnamed-full " not in actual:
    raise SystemExit("Forth program did not complete:\n" + actual.decode(errors="replace"))
host = ["gcc", "-std=gnu99", "-w", "-fno-pie", "-no-pie", "-I" + str(TEST)]
pairings = []
for optimization in ("-O0", "-O2"):
    for name, inputs in (("host-host", [CALLER, CALLEE]),
                         ("forth-caller-host-callee", [forth_caller, CALLEE]),
                         ("host-caller-forth-callee", [CALLER, forth_callee])):
        executable = work / (name + optimization)
        run(host + [optimization, *inputs, "-o", executable])
        expected = run([executable]).stdout
        if actual != expected:
            raise SystemExit(f"{name}{optimization}: output differs\nforth:\n{actual.decode()}\n"
                             f"host:\n{expected.decode()}")
        pairings.append(name + optimization)
F = "struct F { double d; long l; };\n"
rejects = {
    "floating-unprototyped": (232, F + "long f(); long g(struct F v) { return f(v); }\n"),
    "floating-variadic": (232, F + "long f(int, ...); long g(struct F v) { return f(1, v); }\n"),
    "floating-va-arg": (232, "#include <stdarg.h>\n" + F
                        + "long f(int n, ...) { va_list a; va_start(a, n);"
                          " return va_arg(a, struct F).l; }\n"),
    "floating-knr": (232, F + "long f(v) struct F v; { return v.l; }\n"),
    "float-knr-parameter": (232, "struct A { long l; };\n"
                            "long f(a, x) struct A a; float x; { return a.l; }\n"),
}
for name, (code, text) in rejects.items():
    source = work / (name + ".c")
    source.write_text(text)
    result = run([sys.executable, DRIVER, "-c", source, "-o", work / (name + ".o")], expected=code)
    if f"error {code}".encode() not in result.stderr or (work / (name + ".o")).exists():
        raise SystemExit(f"{name}: missing error {code} or output published: {result.stderr!r}")
report = {"lines": actual.count(b"\n"), "pairings": pairings, "rejects": sorted(rejects),
          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in (CALLER, CALLEE, TEST / "record-varargs.h", Path(__file__),
                                      ROOT / "126-cc-varargs.fth",
                                      ROOT / "131-cc-aggregate-abi.fth")},
          "forth_sha256": hashlib.sha256((work / "forth").read_bytes()).hexdigest()}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: records to unprototyped and variadic functions match host GCC on "
      f"{report['lines']} lines in {len(pairings)} host pairings; {len(rejects)} rejections",
      flush=True)
print(work / "report.json")
