#!/usr/bin/env python3
"""-Werror=implicit-function-declaration in the Forth driver.

C90 accepts a call to an undeclared function as `extern int f ();`, which on
LP64 truncates pointer and double results. With the GCC option spelling the
driver makes such a call error 228, naming the function and its source file
and line (through the preprocessor's line map) as host GCC does for the same
option; without it the default C90 behaviour is unchanged. Host GCC is the
oracle for the reported function, file and line.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "tools/gcc-direct-cc.py"
OPTION = "-Werror=implicit-function-declaration"
LIMIT = 1024 ** 3
HEADER = '/* a header\n   with a comment */\nint helper(int);\n#include "nested.h"\n'
NESTED = 'static int nested(void) { return helper(1); }\n'
CASES = {
    # name: (main file, files, compile spelling, -I options)
    "first-line": ("a.c", {"a.c": "int main(void) { return absent(); }\n"}, "a.c", []),
    "after-system-header": ("a.c", {"a.c": '#include <stdio.h>\n#include <string.h>\n\nint main(void)\n{\n'
                                            '    char *p = (char *)absent_dup("x");\n    return p != 0;\n}\n'}, "a.c", []),
    "after-headers": ("sub/a.c", {"sub/a.c": '#include "local.h"\n#include <stdarg.h>\n'
                                             'int f(int n, ...) { va_list a; va_start(a, n); va_end(a); return n; }\n'
                                             'int helper(int v) { return v; }\n\n'
                                             'int main(void)\n{\n    return nested() + missing_call(2);\n}\n',
                                  "sub/local.h": HEADER, "sub/nested.h": NESTED}, "sub/a.c", []),
    "in-header": ("a.c", {"a.c": '#include <stdio.h>\n#include "inc.h"\nint main(void) { return use(); }\n',
                          "include/inc.h": '/* header */\n\nstatic int use(void)\n{\n    return absent_in_header(3);\n}\n'},
                  "a.c", ["-Iinclude", "-DUNUSED=1"]),
    "splices-and-comments": ("./a.c", {"a.c": 'int main(void)\n{\n    int x = 1 + \\\n        2;\n'
                                             '    /* a\n       comment */\n    x += (int)\n        late_call(x,\n'
                                             '                  x);\n    return x;\n}\n'}, "./a.c", []),
    "line-directive": ("a.c", {"a.c": 'int f(void) { return 0; }\n#line 100 "virtual.c"\n'
                                      'int g(void) { return 1; }\nint main(void) { return undeclared(f(), g()); }\n'},
                       "a.c", []),
    "line-then-include": ("a.c", {"a.c": '#line 50 "v.c"\n#include "h.h"\n\nint main(void) { return h() + z(); }\n',
                                  "h.h": '#line 7\nstatic int h(void)\n{\n    return 2;\n}\n'}, "a.c", []),
}
VALID = ('#include <stdio.h>\n#include <stdarg.h>\n'
         'static int add(int n, ...) { va_list a; int s = 0; va_start(a, n); while (n--) s += va_arg(a, int); va_end(a); return s; }\n'
         'int main(void) { extern char *getenv(); char *(*g)() = getenv; '
         'printf("%d %d\\n", add(3, 1, 2, 3), g("SEED_IMPLICIT_UNSET") == 0); return 0; }\n')


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(command, cwd, expected=0):
    command = [str(part) for part in command]
    result = subprocess.run(command, capture_output=True, timeout=300, preexec_fn=limits, cwd=cwd,
                            env=dict(os.environ, LC_ALL="C"))
    if expected is not None and result.returncode != expected:
        raise SystemExit(f"{command}: exit {result.returncode}, expected {expected}\n"
                         + result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace"))
    return result


(ROOT / "build-out").mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix="implicit-error-", dir=ROOT / "build-out"))
records = {}
for name, (main, files, spelling, includes) in CASES.items():
    base = work / name
    for path, text in files.items():
        (base / path).parent.mkdir(parents=True, exist_ok=True)
        (base / path).write_text(text)
    host = run(["gcc", "-std=gnu89", OPTION, *includes, "-c", spelling, "-o", "host.o"], base, None)
    found = re.search(rb"^(.+?):(\d+):\d+: error: implicit declaration of function .(\w+).",
                      host.stderr, re.M)
    if host.returncode == 0 or not found:
        raise SystemExit(f"{name}: host GCC oracle did not report: {host.stderr!r}")
    expected = (found.group(3), found.group(1), int(found.group(2)))
    # The default is unchanged: C90 implicit declarations still compile.
    run([sys.executable, DRIVER, *includes, "-c", spelling, "-o", "default.o"], base)
    forth = run([sys.executable, DRIVER, OPTION, *includes, "-c", spelling, "-o", "forth.o"], base, 228)
    reported = re.match(rb"implicit declaration of function '(\w+)' at (.+?):(\d+): cc: line \d+: error 228\n",
                        forth.stderr)
    if not reported or (reported.group(1), reported.group(2), int(reported.group(3))) != expected:
        raise SystemExit(f"{name}: expected {expected}, got {forth.stderr!r}")
    if (base / "forth.o").exists():
        raise SystemExit(f"{name}: an object was published")
    records[name] = {"function": expected[0].decode(), "file": expected[1].decode(), "line": expected[2]}
# Declared calls, block-scope declarations and the va_* intrinsics are not
# implicit declarations; the option leaves such a program unchanged.
valid = work / "valid"
valid.mkdir()
(valid / "valid.c").write_text(VALID)
run([sys.executable, DRIVER, OPTION, "valid.c", "-o", "with"], valid)
run([sys.executable, DRIVER, "valid.c", "-o", "without"], valid)
if (valid / "with").read_bytes() != (valid / "without").read_bytes():
    raise SystemExit("the option changed a program without implicit declarations")
if run([valid / "with"], valid).stdout != b"6 1\n":
    raise SystemExit("valid program output differs")
report = {"cases": records, "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                              for p in (Path(__file__), DRIVER, ROOT / "040-cc-prep.fth",
                                                        ROOT / "121-cc-sysv.fth")}}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: {OPTION} names the function, file and line as host GCC does in {len(records)} cases; "
      "default C90 behaviour and declared programs unchanged", flush=True)
print(work / "report.json")
