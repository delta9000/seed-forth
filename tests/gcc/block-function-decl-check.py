#!/usr/bin/env python3
"""Block-scope function declarations: extern char *getenv (); in a block.

The Forth-built program and host GCC/glibc C90 builds (-O0/-O2, the
independent oracle) must print identical bytes, including a getenv result
on the stack above 4 GiB and a provider's pointer above 4 GiB. The
self-contained program must also run from the whole-program System V
target. Forbidden shapes must fail with their documented codes.
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
SOURCE = ROOT / "tests/gcc/block-function-decl.c"
PROVIDER = ROOT / "tests/gcc/block-function-decl-provider.c"
LOCAL = ROOT / "tests/gcc/block-function-decl-local.c"
DRIVER = ROOT / "tools/gcc-direct-cc.py"
LIMIT = 1024 ** 3
ENV = dict(os.environ, BLOCK_FN_VALUE="block-scope-value")


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
work = Path(tempfile.mkdtemp(prefix="block-function-decl-", dir=ROOT / "build-out"))
run([sys.executable, DRIVER, SOURCE, PROVIDER, "-o", work / "forth"])
actual = run([work / "forth"]).stdout
if (b"extern getenv block-scope-value above-4GiB 1\n" not in actual
        or b"high 123456789a0\n" not in actual or not actual.endswith(b"failures 0\n")):
    raise SystemExit("Forth program did not complete:\n" + actual.decode(errors="replace"))
for optimization in ("-O0", "-O2"):
    host = work / ("host" + optimization)
    run(["gcc", "-std=c90", "-pedantic-errors", "-Wall", "-Wextra", "-Werror", optimization,
         SOURCE, PROVIDER, "-o", host])
    expected = run([host]).stdout
    if actual != expected:
        raise SystemExit(f"{optimization}: output differs\nforth:\n{actual.decode()}\nhost:\n{expected.decode()}")
# The self-contained program exits 0 from every route.
run([sys.executable, DRIVER, LOCAL, "-o", work / "local-forth"])
run([work / "local-forth"])
run(["bash", ROOT / "tests/gcc/sysv-compile.sh", LOCAL, work / "local-program"])
run([work / "local-program"])
run(["gcc", "-std=c90", "-pedantic-errors", "-Wall", "-Wextra", "-Werror", LOCAL,
     "-o", work / "local-host"])
run([work / "local-host"])
# C90 6.5.1: a block-scope function declaration has no storage class other
# than extern (233), and a block holds no function definition (238). The
# declaration names the one external function, so its type must agree with
# every other declaration of it (237), and it ends with its block (93).
rejects = {
    "static": (233, "int f(void){ static int g(); return 0; }\n"),
    "auto": (233, "int f(void){ auto int g(); return 0; }\n"),
    "register": (233, "int f(void){ register int g(); return 0; }\n"),
    "identifier-list": (233, "int f(void){ extern int g(a, b); return 0; }\n"),
    "nested-definition": (238, "int f(void){ int g(void){ return 1; } return g(); }\n"),
    "later-definition": (237, "int f(void){ extern char *g(); return g() != 0; }\n"
                              "int g(void){ return 0; }\n"),
    "file-prototype": (237, "int g(int); int f(void){ extern long g(); return 0; }\n"),
    "other-block": (237, "int f(void){ extern long g(); return 0; }\n"
                         "int h(void){ extern int g(); return 0; }\n"),
    "implicit-call": (237, "int f(void){ return g(); }\n"
                           "int h(void){ extern char *g(); return 0; }\n"),
    "later-static": (237, "int f(void){ extern int g(); return g(); }\n"
                          "static int g(void){ return 1; }\n"),
    "out-of-scope": (93, "int f(void){ { extern int g(); } return g; }\n"),
}
for name, (code, text) in rejects.items():
    source = work / (name + ".c")
    source.write_text(text)
    result = run([sys.executable, DRIVER, "-c", source, "-o", work / (name + ".o")], expected=code)
    if f"error {code}".encode() not in result.stderr:
        raise SystemExit(f"{name}: missing error {code}: {result.stderr!r}")
report = {"lines": actual.count(b"\n"), "host_oracles": ["-O0", "-O2"], "rejects": sorted(rejects),
          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in (SOURCE, PROVIDER, LOCAL, Path(__file__),
                                      ROOT / "121-cc-sysv.fth", ROOT / "123-cc-object-program.fth")},
          "forth_sha256": hashlib.sha256((work / "forth").read_bytes()).hexdigest()}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: block-scope function declarations match host GCC on {report['lines']} lines; "
      f"whole-program route runs; {len(rejects)} rejections", flush=True)
print(work / "report.json")
