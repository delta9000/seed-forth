#!/usr/bin/env python3
"""GCC driver runtime gate: dup, chdir, link, rename, putenv, fscanf, sys/param.h.

The Forth-built program and host GCC/glibc builds (-O0/-O2, the independent
oracle) run serially under a one-GiB limit, each in its own fresh directory
with the same controlled environment, and must print identical bytes. Host
GCC also lints the changed runtime sources against the runtime headers alone.
"""
from pathlib import Path
import hashlib
import json
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/gcc/driver-runtime-check.c"
RUNTIME = ROOT / "runtime/gcc-seed"
LIMIT = 1024 ** 3
ENVIRONMENT = {"SEED_START": "startup", "PATH": "/usr/bin:/bin"}


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(command, **kwargs):
    command = [str(part) for part in command]
    result = subprocess.run(command, capture_output=True, timeout=300, preexec_fn=limits, **kwargs)
    if result.returncode:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result.stdout


def exercise(executable, name):
    directory = work / ("run-" + name)
    (directory / "sub").mkdir(parents=True)
    (directory / "sub/inner").write_text("inner\n")
    output = run([executable], cwd=directory, env=ENVIRONMENT)
    left = sorted(str(p.relative_to(directory)) for p in directory.rglob("*"))
    if left != ["sub", "sub/inner"]:
        raise SystemExit(f"{name}: directory left as {left}")
    return output


(ROOT / "build-out").mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix="driver-runtime-", dir=ROOT / "build-out"))
run([sys.executable, ROOT / "tools/gcc-direct-cc.py", SOURCE, "-o", work / "forth"])
actual = exercise(work / "forth", "forth")
if not actual.endswith(b"done\n") or b"MAXPATHLEN 4096\n" not in actual:
    raise SystemExit("Forth program did not complete:\n" + actual.decode(errors="replace"))
for optimization in ("-O0", "-O2"):
    host = work / ("host" + optimization)
    run(["gcc", "-std=c99", "-pedantic", "-Wall", "-Wextra", "-Werror", optimization,
         "-fno-builtin", "-U_FORTIFY_SOURCE", "-D_GNU_SOURCE", SOURCE, "-o", host])
    expected = exercise(host, optimization[1:])
    if actual != expected:
        for n, (a, e) in enumerate(zip(actual.splitlines(), expected.splitlines()), 1):
            if a != e:
                raise SystemExit(f"line {n}: forth {a!r} != host {e!r}")
        raise SystemExit("output lengths differ")
# Host stdarg.h replaces the runtime's (same ABI, Forth-specific spelling).
lint = work / "lint-include"
lint.mkdir()
compiler_include = run(["gcc", "-print-file-name=include"]).decode().strip()
(lint / "stdarg.h").write_text(f'#include "{compiler_include}/stdarg.h"\n')
LINT = ["gcc", "-std=c90", "-pedantic", "-fsyntax-only", "-nostdinc", "-isystem", lint,
        "-isystem", RUNTIME / "include", "-Wall", "-Wextra", "-Werror",
        "-Wno-builtin-declaration-mismatch"]
names = ["paths.c", "environment.c", "scan.c", "process-api.c"]
for name in names:
    run(LINT + [RUNTIME / name])
run(LINT + ["-Wno-unused-result", SOURCE])
sources = [SOURCE, Path(__file__), RUNTIME / "include/sys/param.h", RUNTIME / "include/unistd.h",
           RUNTIME / "include/stdio.h", RUNTIME / "include/stdlib.h"] + [RUNTIME / n for n in names]
report = {"lines": actual.count(b"\n"), "host_oracles": ["-O0", "-O2"],
          "memory_limit_bytes": LIMIT, "environment": ENVIRONMENT,
          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in sources},
          "forth_sha256": hashlib.sha256((work / "forth").read_bytes()).hexdigest()}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: driver runtime matches host glibc on {report['lines']} lines", flush=True)
print(work / "report.json")
