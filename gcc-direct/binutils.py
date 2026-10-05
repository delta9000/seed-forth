#!/usr/bin/env python3
"""Build original binutils 2.30 stage B with the frozen Forth toolchain.

Usage:
    python3 gcc-direct/binutils.py WORK --oyacc OYACC --flex FLEX [-j JOBS]

First run configure.py --package binutils --forth-ar --work WORK.  Configure
verifies the pinned release and makes a source view omitting shipped generated
parser/scanner C and headers (recorded in source-view.json).  The original
Makefiles must regenerate those files from .y/.l with Forth-built tools rather
than reuse release-generated C.  Hand-written parser headers remain intact.

From WORK/build/top, use the environment in configure-command.json and LC_ALL=C
for stable diagnostics.  Empty CFLAGS/LDFLAGS avoid unsupported debug/optimization
and host-link flags selected by Makefile templates.  Empty WARN_CFLAGS and
WARN_WRITE_STRINGS suppress unsupported GCC warnings: bfd/warning.m4 (near line
57) assumes any __GNUC__ not expanding to 0-3 means GCC 4+, adding
-Wwrite-strings, which the Forth driver rejects by design.  YACC/BISON both name
OYACC and LEX/FLEX both name FLEX to cover the original Makefiles' variable
spellings without falling back to host parser generators.

make -k builds all-gas, all-ld and all-binutils, keeping going after failures,
then makes gas, ld and binutils directly (the top level's MAKEOVERRIDES= drops
the WARN_* overrides on the way down);
jobs default to six (each Forth compile can use a few hundred MiB).  WORK must be new, as configure.py
rejects existing directories.  No host compiler produces route artifacts.

WORK/stage-b/report.json and report.md record executable hashes and every failed
compile/link invocation in WORK/probes, excluding configure's conftest probes
and preprocessing-only calls.  Diagnostics are grouped after removing source
line numbers, as in the scratch stage-B census.  Configure answers remain
provisional; built executables are not an execution or bootstrap proof.
"""
from pathlib import Path
import argparse
import collections
import hashlib
import json
import os
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ("gas/as-new", "ld/ld-new", "binutils/ar", "binutils/nm-new",
         "binutils/objdump", "binutils/readelf")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, cwd, environment, log):
    started = time.time()
    with log.open("wb") as stream:
        result = subprocess.run(command, cwd=cwd, env=environment,
                                stdout=stream, stderr=subprocess.STDOUT)
    return {"command": command, "cwd": str(cwd), "returncode": result.returncode,
            "seconds": round(time.time() - started, 1), "log": str(log)}


def build_traces(work):
    failures = []
    successful = 0
    build = work / "build/top"
    for invocation in sorted((work / "probes").glob("*/invocation.json")):
        record = json.loads(invocation.read_text())
        arguments = record["arguments"]
        if "conftest" in " ".join(arguments) or "-E" in arguments:
            continue
        if not ("-c" in arguments or "-o" in arguments):
            continue
        if record["returncode"] == 0:
            successful += 1
            continue
        cwd = Path(record["cwd"])
        directory = cwd.relative_to(build).as_posix() if cwd.is_relative_to(build) else str(cwd)
        sources = [a for a in arguments if a.endswith(".c")]
        stderr = (invocation.parent / "stderr").read_text(errors="replace").strip().splitlines()
        diagnostic = stderr[0] if stderr else ""
        failures.append({"kind": "compile" if "-c" in arguments else "link",
                         "dir": directory, "source": Path(sources[-1]).name if sources else "?",
                         "diagnostic": diagnostic,
                         "diagnostic_group": re.sub(r"line \d+: ", "", diagnostic),
                         "returncode": record["returncode"], "arguments": arguments,
                         "trace": str(invocation.parent.relative_to(work))})
    return successful, failures


def cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def report(work, args, steps):
    out = work / "stage-b"
    out.mkdir()
    tools = []
    for name in TOOLS:
        path = work / "build/top" / name
        tool = {"path": name, "built": path.is_file() and os.access(path, os.X_OK)}
        if tool["built"]:
            tool.update(sha256=sha(path), bytes=path.stat().st_size)
        tools.append(tool)
    successful, failures = build_traces(work)
    groups = collections.Counter(f["diagnostic_group"] for f in failures)
    toolchain = work / "toolchain-inputs.json"
    inputs = json.loads(toolchain.read_text()) if toolchain.is_file() else None
    source = work / "gcc-source-inputs.json"
    summary = {
        "scope": "Original binutils stage-B build; configure answers provisional; no execution or bootstrap claim",
        "compiler_inputs_sha256": hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest() if inputs else None,
        "binutils_source_sha256": json.loads(source.read_text())["archive_sha256"] if source.is_file() else None,
        "oyacc_sha256": sha(args.oyacc), "flex_sha256": sha(args.flex),
        "jobs": args.jobs, "steps": steps, "tools": tools,
        "built": sum(t["built"] for t in tools), "successful_invocations": successful,
        "failed_invocations": len(failures), "failures": failures,
        "diagnostic_groups": [{"diagnostic": diagnostic, "count": count}
                              for diagnostic, count in groups.most_common()],
    }
    (out / "report.json").write_text(json.dumps(summary, indent=2) + "\n")
    lines = [f"# binutils stage B: {summary['built']} of {len(tools)} tools built", "",
             summary["scope"], "", f"Jobs: {args.jobs}. Successful compile/link invocations: {successful}; failed: {len(failures)}.", ""]
    for step in steps:
        lines.append(f"{step['command'][0]}: exit {step['returncode']}, {step['seconds']} s; log: {step['log']}")
    lines += ["", "| Tool | Built | SHA256 |", "|---|---|---|"]
    for tool in tools:
        lines.append(f"| {tool['path']} | {'yes' if tool['built'] else 'no'} | {tool.get('sha256', '')} |")
    lines += ["", "## Diagnostic groups", "", "| Count | Diagnostic (line numbers removed) |", "|---|---|"]
    for diagnostic, count in groups.most_common():
        lines.append(f"| {count} | {cell(diagnostic)} |")
    lines += ["", "## Failed compile and link invocations", "",
              "| Kind | Directory | Source | First diagnostic | Trace |", "|---|---|---|---|---|"]
    for failure in failures:
        lines.append("| " + " | ".join(cell(failure[key]) for key in
                     ("kind", "dir", "source", "diagnostic", "trace")) + " |")
    (out / "report.md").write_text("\n".join(lines) + "\n")
    print(f"{summary['built']} of {len(tools)} tools built; {len(failures)} failed compile/link invocations", flush=True)
    print(out / "report.md", flush=True)
    return 0 if all(t["built"] for t in tools) and all(s["returncode"] == 0 for s in steps) else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("work", type=Path, help="new configure/build directory")
    parser.add_argument("--oyacc", type=Path, required=True, help="Forth-built oyacc executable")
    parser.add_argument("--flex", type=Path, required=True, help="Forth-built flex executable")
    parser.add_argument("-j", "--jobs", type=int, default=6, help="parallel make jobs (default 6)")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("jobs must be at least 1")
    for name in ("oyacc", "flex"):
        path = getattr(args, name).resolve()
        if not path.is_file() or not os.access(path, os.X_OK):
            parser.error(f"--{name} must name an executable file: {path}")
        setattr(args, name, path)
    work = args.work.resolve()
    if work.exists():
        parser.error(f"work directory already exists: {work}")
    work.parent.mkdir(parents=True, exist_ok=True)
    configure = [sys.executable, str(ROOT / "gcc-direct/configure.py"),
                 "--package", "binutils", "--forth-ar", "--work", str(work)]
    print(f"Configuring binutils: {work}", flush=True)
    steps = [run(configure, ROOT, os.environ.copy(), Path(str(work) + ".configure.out"))]
    print(f"Configure exit {steps[-1]['returncode']}", flush=True)
    if not work.exists():
        print(f"Configure did not create WORK; see {steps[-1]['log']}", file=sys.stderr)
        return 1
    if steps[-1]["returncode"] == 0:
        recorded = json.loads((work / "configure-command.json").read_text())
        environment = os.environ.copy()
        environment.update(recorded["environment"])
        environment["LC_ALL"] = "C"
        overrides = ["CFLAGS=", "LDFLAGS=", "WARN_CFLAGS=", "WARN_WRITE_STRINGS=",
                     f"YACC={args.oyacc}", f"BISON={args.oyacc}",
                     f"LEX={args.flex}", f"FLEX={args.flex}"]
        command = ["make", "-k", "-j", str(args.jobs), *overrides, "all-gas", "all-ld", "all-binutils"]
        print(f"Building binutils with {args.jobs} jobs; log: {work / 'make.log'}", flush=True)
        steps.append(run(command, work / "build/top", environment, work / "make.log"))
        print(f"Make exit {steps[-1]['returncode']}", flush=True)
        # The top-level Makefile sets MAKEOVERRIDES= and forwards only its
        # FLAGS_TO_PASS lists, so the WARN_* overrides never reach the tool
        # directories.  Their libraries are built and their Makefiles configured
        # by now; make each tool directory directly with the same overrides.
        for directory in ("gas", "ld", "binutils"):
            if not (work / "build/top" / directory / "Makefile").is_file():
                print(f"{directory} not configured; skipped", flush=True)
                continue
            command = ["make", "-k", "-j", str(args.jobs), *overrides]
            steps.append(run(command, work / "build/top" / directory, environment,
                             work / f"make-{directory}.log"))
            print(f"Make {directory} exit {steps[-1]['returncode']}", flush=True)
    return report(work, args, steps)


if __name__ == "__main__":
    sys.exit(main())
