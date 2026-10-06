#!/usr/bin/env python3
"""__FILE__ is spelled as on the command line, as GCC spells it.

GCC expands __FILE__ in the main file to the name as given (`a.c`, `./a.c`,
`sub/a.c`, an absolute path) and in a header to the directory as found plus
the include name: the including file's directory for a quote include, or the
-I directory as given. The Forth driver must print the same strings for every
combination of source spelling and -I spelling, with host GCC as the oracle.
An object that uses assert() then does not depend on the build directory:
the same relative command in two directories produces identical bytes.
"""
from pathlib import Path
import hashlib
import itertools
import json
import os
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "tools/gcc-direct-cc.py"
LIMIT = 1024 ** 3
MAIN = ('#include <stdio.h>\n#include "loc.h"\n#include "x.h"\n#include <deep/y.h>\n'
        'int main(void) { puts(__FILE__); puts(LOC); puts(XF); puts(YF); return 0; }\n')
ASSERTING = '#include <assert.h>\nint check(int v) { assert(v > 0); return v; }\n'


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(command, cwd, expected=0):
    command = [str(part) for part in command]
    result = subprocess.run(command, capture_output=True, timeout=300, preexec_fn=limits, cwd=cwd)
    if result.returncode != expected:
        raise SystemExit(f"{command} in {cwd}: exit {result.returncode}, expected {expected}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


def tree(base):
    for directory in ("sub", "inc/deep"):
        (base / directory).mkdir(parents=True, exist_ok=True)
    for name in ("a.c", "sub/a.c"):
        (base / name).write_text(MAIN)
    for name in ("loc.h", "sub/loc.h"):
        (base / name).write_text('static const char *locf = __FILE__;\n#define LOC locf\n')
    (base / "inc/x.h").write_text('static const char *xf = __FILE__;\n#define XF xf\n')
    (base / "inc/deep/y.h").write_text('static const char *yf = __FILE__;\n#define YF yf\n')


(ROOT / "build-out").mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix="file-spelling-", dir=ROOT / "build-out"))
base = work / "tree"
tree(base)
sources = ["a.c", "./a.c", "sub/a.c", ".//a.c", str(base / "a.c"), str(base / "sub/a.c")]
includes = ["-Iinc", "-Iinc/", "-I./inc", "-Iinc//", "-I" + str(base / "inc")]
cases = []
for index, (source, include) in enumerate(itertools.product(sources, includes)):
    forth, host = work / f"forth-{index}", work / f"host-{index}"
    run([sys.executable, DRIVER, include, source, "-o", forth], base)
    run(["gcc", include, source, "-o", host], base)
    actual, expected = run([forth], base).stdout, run([host], base).stdout
    if actual != expected:
        raise SystemExit(f"{source} {include}: __FILE__ differs\nforth:\n{actual.decode()}\n"
                         f"host:\n{expected.decode()}")
    cases.append({"source": source, "include": include, "lines": actual.decode().splitlines()})
# Relative spellings make objects independent of the directory holding them.
objects = []
for name in ("one", "two/deeper"):
    directory = work / name
    directory.mkdir(parents=True)
    (directory / "check.c").write_text(ASSERTING)
    run([sys.executable, DRIVER, "-c", "check.c", "-o", "check.o"], directory)
    objects.append((directory / "check.o").read_bytes())
if objects[0] != objects[1] or b"check.c\0" not in objects[0] or str(work).encode() in objects[0]:
    raise SystemExit("assert() object depends on its build directory")
# The preprocessor still opens files through the spellings it reports.
(base / "missing.c").write_text('#include "absent.h"\nint main(void) { return 0; }\n')
result = run([sys.executable, DRIVER, "-Iinc", "missing.c", "-o", work / "missing"], base, expected=30)
report = {"cases": cases, "identical_objects_sha256": hashlib.sha256(objects[0]).hexdigest(),
          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in (Path(__file__), DRIVER, ROOT / "040-cc-prep.fth")}}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: __FILE__ matches host GCC for {len(cases)} source/-I spellings; "
      "assert objects are independent of the build directory", flush=True)
print(work / "report.json")
