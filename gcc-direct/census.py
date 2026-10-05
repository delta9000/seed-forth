#!/usr/bin/env python3
"""Compile every original GCC 4.0.4 cc1 translation unit with the Forth compiler.

Usage:
    gcc-direct/census.py WORK --oyacc OYACC --flex FLEX [-j JOBS]

WORK holds fresh `gcc`, `libiberty` and `libcpp` directories made by
`gcc-direct/configure.py --work WORK/<component>` from one compiler commit.
OYACC and FLEX are the Forth-built parser generators (see
`tests/gcc/oyacc-check.py` and the lexer recipe); host bison/flex are never used.

The original Makefiles do all the work: they decide which objects cc1 needs,
build and run the generator programs with the Forth compiler, and compile each
object with its real flags.  The only overrides are the ones configure cannot
express: empty CFLAGS/LDFLAGS (the template hardcodes -g), the parser
generators, and the libiberty archive path.  `make -k` keeps going past
failures so that one census reports every unit.

Every compiler call is already traced by `configure.py --invoke` under
WORK/gcc/probes/ (argv, inputs, stdout, stderr, return code, outputs).
This script records, per cc1 object: built or not, its hash and size, and for
failures the compiler's own diagnostic.  Results go to WORK/census/.

A successful census means objects compiled.  It does not mean cc1 links or runs.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make(build, environment, arguments, log):
    command = ["make", *arguments]
    started = time.time()
    with log.open("ab") as stream:
        stream.write(("\n$ " + " ".join(command) + "\n").encode())
        stream.flush()
        result = subprocess.run(command, cwd=build, env=environment, stdout=stream, stderr=subprocess.STDOUT)
    return {"command": command, "cwd": str(build), "returncode": result.returncode,
            "seconds": round(time.time() - started, 1)}


def environment_for(component_work):
    recorded = json.loads((component_work / "configure-command.json").read_text())
    environment = os.environ.copy()
    environment.update(recorded["environment"])
    environment["LC_ALL"] = "C"
    return environment


def cc1_objects(build, environment, scratch):
    """Ask the configured Makefile itself which objects cc1 is linked from."""
    printer = scratch / "print-cc1-objects.mk"
    printer.write_text("print-cc1-objects:\n\t@echo $(sort $(C_OBJS) main.o $(OBJS))\n")
    output = subprocess.run(["make", "-s", "-f", "Makefile", "-f", str(printer), "print-cc1-objects"],
                            cwd=build, env=environment, check=True, capture_output=True, text=True).stdout
    return output.split()


def compile_traces(probes):
    """Map each object path to the last compiler invocation that targeted it."""
    traces = {}
    for invocation in sorted(probes.glob("*/invocation.json")):
        record = json.loads(invocation.read_text())
        arguments, cwd = record["arguments"], Path(record["cwd"])
        if "-c" not in arguments:
            continue
        target = None
        for index, argument in enumerate(arguments):
            if argument == "-o" and index + 1 < len(arguments):
                target = arguments[index + 1]
        if target is None:
            sources = [a for a in arguments if a.endswith(".c")]
            target = Path(sources[-1]).stem + ".o" if sources else None
        if target:
            traces[str((cwd / target).resolve())] = (invocation.parent, record)
    return traces


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("work", type=Path)
    parser.add_argument("--oyacc", type=Path, required=True)
    parser.add_argument("--flex", type=Path, required=True)
    parser.add_argument("-j", "--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 4))
    args = parser.parse_args()
    work = args.work.resolve()
    out = work / "census"
    out.mkdir()
    log = out / "make.log"
    steps = []

    libiberty_build = work / "libiberty/build/libiberty"
    libiberty = libiberty_build / "libiberty.a"
    steps.append(make(libiberty_build, environment_for(work / "libiberty"),
                      ["-j", str(args.jobs), "CFLAGS=", "LDFLAGS=", "libiberty.a"], log))

    gcc_build = work / "gcc/build/gcc"
    environment = environment_for(work / "gcc")
    overrides = ["CFLAGS=", "LDFLAGS=",
                 f"BISON={args.oyacc.resolve()}", f"FLEX={args.flex.resolve()}",
                 f"LIBIBERTY={libiberty}", f"BUILD_LIBIBERTY={libiberty}"]
    objects = cc1_objects(gcc_build, environment, out)
    (out / "objects.txt").write_text("\n".join(objects) + "\n")
    print(f"{len(objects)} cc1 objects; make log: {log}", flush=True)

    started = time.time()
    steps.append(make(gcc_build, environment, ["-k", "-j", str(args.jobs), *overrides, *objects], log))
    elapsed = round(time.time() - started, 1)

    traces = compile_traces(work / "gcc/probes")
    units = []
    for name in objects:
        path = gcc_build / name
        trace, record = traces.get(str(path.resolve()), (None, None))
        unit = {"object": name, "built": path.is_file()}
        if unit["built"]:
            unit.update(sha256=sha(path), bytes=path.stat().st_size)
        if record is not None:
            unit.update(returncode=int(record["returncode"]), trace=str(trace.relative_to(work)))
            if not unit["built"]:
                unit["stderr"] = (trace / "stderr").read_text(errors="replace").strip()[-400:]
        else:
            unit["note"] = "never compiled (a prerequisite failed; see make.log)"
        units.append(unit)

    built = [u for u in units if u["built"]]
    failed = [u for u in units if not u["built"]]
    toolchain = json.loads((work / "gcc/toolchain-inputs.json").read_text())
    summary = {
        "scope": "Compilation of original cc1 objects only; no link, execution or bootstrap claim",
        "compiler_inputs_sha256": hashlib.sha256(json.dumps(toolchain, sort_keys=True).encode()).hexdigest(),
        "gcc_source_sha256": json.loads((work / "gcc/report.json").read_text())["gcc_source_sha256"],
        "oyacc_sha256": sha(args.oyacc), "flex_sha256": sha(args.flex),
        "jobs": args.jobs, "compile_seconds": elapsed,
        "objects": len(units), "built": len(built), "failed": len(failed),
        "steps": steps, "units": units,
    }
    (out / "census.json").write_text(json.dumps(summary, indent=2) + "\n")
    lines = [f"# cc1 census: {len(built)} of {len(units)} objects compiled", "",
             f"Compiler inputs {summary['compiler_inputs_sha256'][:16]}, {args.jobs} jobs, {elapsed} s.", "",
             "| Failed object | Compiler said |", "|---|---|"]
    for unit in failed:
        said = [line for line in unit.get("stderr", "").splitlines() if " error " in line]
        lines.append(f"| {unit['object']} | {said[-1] if said else unit.get('note', '')} |")
    (out / "census.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
