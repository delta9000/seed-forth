"""Shared driver for the POSIX runtime gates (tests/gcc/posix-*-check.py).

Each gate compiles one C fixture twice: by the Forth compiler against
runtime/gcc-seed (production) and by host GCC against glibc at -O0 and -O2
(the independent oracle). Every program runs serially under a one-GiB
address-space limit in its own fresh directory with the same controlled
environment, and the outputs must match byte for byte. Runtime-only checks
in a fixture sit under `#ifndef __GLIBC__` and print nothing on success, so
they never reach the comparison. Host GCC also lints the named runtime
sources against the runtime headers alone.
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
RUNTIME = ROOT / "runtime/gcc-seed"
LIMIT = 1024 ** 3
ENVIRONMENT = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "HOME": "/nonexistent",
               "SEED_POSIX": "fixture"}


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


class Gate:
    def __init__(self, name, fixture, sources):
        (ROOT / "build-out").mkdir(exist_ok=True)
        self.name = name
        self.fixture = ROOT / "tests/gcc" / fixture
        self.sources = [RUNTIME / source for source in sources]
        self.work = Path(tempfile.mkdtemp(prefix=name + "-", dir=ROOT / "build-out"))
        self.programs = {}
        self.report = {"gate": name, "host_oracles": ["-O0", "-O2"],
                       "memory_limit_bytes": LIMIT, "environment": ENVIRONMENT}

    def run(self, command, status=0, **kwargs):
        command = [str(part) for part in command]
        kwargs.setdefault("env", ENVIRONMENT)
        result = subprocess.run(command, capture_output=True, timeout=300,
                                preexec_fn=limits, **kwargs)
        if status is not None and result.returncode != status:
            raise SystemExit(f"{command}: exit {result.returncode}, wanted {status}\n"
                             + result.stdout.decode(errors="replace")[-3000:]
                             + result.stderr.decode(errors="replace")[-3000:])
        return result

    def build(self, extra_host=()):
        """Forth program plus host -O0/-O2 oracles of the same fixture."""
        forth = self.work / "forth"
        self.run([sys.executable, ROOT / "tools/gcc-direct-cc.py", "-static", self.fixture, "-o", forth],
                 env=dict(os.environ))
        self.programs["forth"] = forth
        for optimization in ("-O0", "-O2"):
            host = self.work / ("host" + optimization)
            self.run(["gcc", "-std=c99", "-pedantic", "-Wall", "-Wextra", "-Werror", "-Wno-deprecated-declarations", optimization,
                      "-fno-builtin", "-U_FORTIFY_SOURCE", "-D_GNU_SOURCE", self.fixture,
                      *extra_host, "-o", host], env=dict(os.environ))
            self.programs["host" + optimization] = host
        return self.programs

    def directory(self, label):
        path = self.work / ("run-" + label)
        path.mkdir()
        return path

    def compare(self, arguments=(), prepare=None, status=0, stdin=None, label="", env=None, wrapper=()):
        """Run every build with ARGUMENTS in fresh directories; outputs must
        match the Forth program's. PREPARE(directory) populates each one;
        WRAPPER is a command prefix (for example a namespace launcher)."""
        outputs = {}
        for name, program in self.programs.items():
            directory = self.directory(name + label)
            if prepare:
                prepare(directory)
            result = self.run([*wrapper, program, *arguments], status=status, cwd=directory,
                              input=stdin, env=env or ENVIRONMENT)
            outputs[name] = result.stdout + b"--stderr--\n" + result.stderr
        actual = outputs["forth"]
        for name, expected in outputs.items():
            if expected != actual:
                for number, (a, e) in enumerate(zip(actual.splitlines(), expected.splitlines()), 1):
                    if a != e:
                        raise SystemExit(f"{self.name}{label}: line {number}: forth {a!r} != {name} {e!r}")
                raise SystemExit(f"{self.name}{label}: forth and {name} output lengths differ\n"
                                 + actual.decode(errors="replace")[-2000:] + "\n---\n"
                                 + expected.decode(errors="replace")[-2000:])
        return actual

    def lint(self):
        lint = self.work / "lint-include"
        lint.mkdir(exist_ok=True)
        compiler_include = self.run(["gcc", "-print-file-name=include"], env=dict(os.environ)).stdout.decode().strip()
        (lint / "stdarg.h").write_text(f'#include "{compiler_include}/stdarg.h"\n')
        for source in self.sources:
            self.run(["gcc", "-std=c99", "-pedantic", "-fsyntax-only", "-nostdinc", "-isystem", lint,
                      "-isystem", RUNTIME / "include", "-Wall", "-Wextra", "-Werror",
                      "-Wno-builtin-declaration-mismatch", source], env=dict(os.environ))

    def finish(self, lines, **extra):
        files = [self.fixture, Path(sys.argv[0]).resolve(), Path(__file__)] + self.sources
        self.report.update(extra)
        self.report["compared_lines"] = lines
        self.report["source_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                        for p in files}
        self.report["forth_sha256"] = hashlib.sha256(self.programs["forth"].read_bytes()).hexdigest()
        (self.work / "report.json").write_text(json.dumps(self.report, indent=2) + "\n")
        print(f"PASS: {self.name}: Forth runtime matches host glibc on {lines} lines", flush=True)
        print(self.work / "report.json")
