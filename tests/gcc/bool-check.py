#!/usr/bin/env python3
"""C99 _Bool and <stdbool.h> against host GCC as an oracle.

bool-main.c converts integers, pointers, function pointers and binary32/
binary64 values (NaN, signed zero, infinity, a subnormal) to _Bool, uses
++, --, compound assignment, promotions, casts, static and enum constants,
arrays, record members and _Bool bitfields; bool-provider.c passes _Bool
arguments, results and records across the System V boundary. The units are
compiled by Forth and by host GCC (-O0/-O2) and every pairing must print the
same bytes. Invalid or unsupported forms keep their documented codes.
"""
from pathlib import Path
import hashlib
import json
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TEST = ROOT / "tests/gcc"
MAIN = TEST / "bool-main.c"
PROVIDER = TEST / "bool-provider.c"
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
work = Path(tempfile.mkdtemp(prefix="bool-", dir=ROOT / "build-out"))
forth_main, forth_provider = work / "main.o", work / "provider.o"
run([sys.executable, DRIVER, "-c", MAIN, "-o", forth_main])
run([sys.executable, DRIVER, "-c", PROVIDER, "-o", forth_provider])
run([sys.executable, DRIVER, forth_main, forth_provider, "-o", work / "forth"])
actual = run([work / "forth"]).stdout
if not actual.startswith(b"init 1 1 0 size 1 1 3 defined 1\n") or not actual.endswith(b"store 1 1 0 0\n"):
    raise SystemExit("Forth program did not complete:\n" + actual.decode(errors="replace"))
host = ["gcc", "-std=c99", "-pedantic-errors", "-fno-pie", "-no-pie", "-I" + str(TEST)]
pairings = []
for optimization in ("-O0", "-O2"):
    for name, inputs in (("host-host", [MAIN, PROVIDER]),
                         ("forth-main-host-provider", [forth_main, PROVIDER]),
                         ("host-main-forth-provider", [MAIN, forth_provider])):
        executable = work / (name + optimization)
        run(host + [optimization, *inputs, "-o", executable])
        expected = run([executable]).stdout
        if actual != expected:
            raise SystemExit(f"{name}{optimization}: output differs\nforth:\n{actual.decode()}\n"
                             f"host:\n{expected.decode()}")
        pairings.append(name + optimization)
rejects = {
    # C99 6.7.2: _Bool combines with no other type specifier.
    "unsigned-bool": (233, "unsigned _Bool x;\n"),
    "long-bool": (233, "long _Bool x;\n"),
    "bool-int": (233, "_Bool int x;\n"),
    # C99 6.7.2.1: a _Bool bitfield is at most one bit wide.
    "wide-bitfield": (248, "struct s { _Bool b : 2; };\n"),
    # _Bool promotes to int, so va_arg cannot request it, as for char.
    "va-arg": (247, "#include <stdarg.h>\n"
                    "int f(int n, ...) { va_list a; va_start(a, n); return va_arg(a, _Bool); }\n"),
    # Not implemented: an address constant converted to _Bool at compile time.
    "static-address": (238, "int x; static _Bool b = &x;\n"),
    # Records have no scalar truth conversion.
    "record": (232, "struct A { int a; }; void f(struct A a) { _Bool b = a; }\n"),
}
source = work / "long-double.c"
source.write_text("_Bool f(long double *x) { _Bool b; b = *x; return b; }\n")
run([sys.executable, DRIVER, "-c", source, "-o", work / "long-double.o"])
for name, (code, text) in rejects.items():
    source = work / (name + ".c")
    source.write_text(text)
    result = run([sys.executable, DRIVER, "-c", source, "-o", work / (name + ".o")], expected=code)
    if f"error {code}".encode() not in result.stderr or (work / (name + ".o")).exists():
        raise SystemExit(f"{name}: missing error {code} or output published: {result.stderr!r}")
report = {"lines": actual.count(b"\n"), "pairings": pairings, "rejects": sorted(rejects),
          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in (MAIN, PROVIDER, TEST / "bool.h", Path(__file__),
                                      ROOT / "runtime/gcc-seed/include/stdbool.h")},
          "forth_sha256": hashlib.sha256((work / "forth").read_bytes()).hexdigest()}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: _Bool and <stdbool.h> match host GCC on {report['lines']} lines in "
      f"{len(pairings)} host pairings; {len(rejects)} rejections", flush=True)
print(work / "report.json")
