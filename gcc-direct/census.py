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

With --link it also archives libcpp and lets the Makefile link cc1 with the
Forth linker.  A successful census means objects compiled (and, with --link,
that cc1 linked).  It does not show that cc1 behaves correctly.

When host GCC is available it is used as a lint oracle only: every unit is
syntax-checked against the runtime headers for implicit function
declarations.  Under C90 an undeclared function returns int, so a pointer
result is silently truncated even though the link succeeds (this is how
undeclared bsearch crashed the first cc1 on every VLA).  Any implicit
declaration fails the census and is listed in census/implicit-decls.json.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys
import shutil
import time
from concurrent.futures import ThreadPoolExecutor


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


def implicit_declarations(work, traces, objects, jobs):
    """Names of functions each unit calls without a declaration (host GCC lint)."""
    if shutil.which("gcc") is None:
        return None
    headers = work / "gcc/toolchain/runtime/gcc-seed/include"
    environment = dict(os.environ, LC_ALL="C")

    def lint(name):
        trace = traces.get(str((work / "gcc/build/gcc" / name).resolve()))
        if trace is None:
            return name, []
        record = trace[1]
        arguments = [a for a in record["arguments"] if a.startswith(("-D", "-I", "-U")) or a.endswith(".c")]
        result = subprocess.run(["gcc", "-std=gnu89", "-fsyntax-only", "-nostdinc", "-isystem", str(headers),
                                 "-Wimplicit-function-declaration", *arguments],
                                cwd=record["cwd"], env=environment, capture_output=True, text=True)
        marker = "implicit declaration of function '"
        names = {line.split(marker, 1)[1].split("'", 1)[0] for line in result.stderr.splitlines() if marker in line}
        return name, sorted(names)

    with ThreadPoolExecutor(jobs) as pool:
        return {name: found for name, found in pool.map(lint, objects) if found}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("work", type=Path)
    parser.add_argument("--oyacc", type=Path, required=True)
    parser.add_argument("--flex", type=Path, required=True)
    parser.add_argument("-j", "--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 4))
    parser.add_argument("--link", action="store_true", help="also archive libcpp and link cc1")
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

    if args.link:
        # libcpp's 4.0.4 Makefile hardcodes `AR = ar` with `cru`; the archive is
        # removed just before, so `rc` with the Forth archiver is the same request.
        libcpp_build = work / "libcpp/build/libcpp"
        libcpp_environment = environment_for(work / "libcpp")
        steps.append(make(libcpp_build, libcpp_environment,
                          ["-j", str(args.jobs), "CFLAGS=", "LDFLAGS=",
                           f"AR={libcpp_environment['AR']}", "ARFLAGS=rc", "libcpp.a"], log))
        steps.append(make(gcc_build, environment,
                          [*overrides, f"CPPLIB={libcpp_build / 'libcpp.a'}", "cc1"], log))

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

    implicit = implicit_declarations(work, traces, objects, args.jobs)
    (out / "implicit-decls.json").write_text(json.dumps(implicit, indent=2) + "\n")

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
        "cc1": {"sha256": sha(gcc_build / "cc1"), "bytes": (gcc_build / "cc1").stat().st_size}
               if (gcc_build / "cc1").is_file() else None,
        "implicit_declarations": implicit,
        "steps": steps, "units": units,
    }
    (out / "census.json").write_text(json.dumps(summary, indent=2) + "\n")
    lines = [f"# cc1 census: {len(built)} of {len(units)} objects compiled", "",
             f"Compiler inputs {summary['compiler_inputs_sha256'][:16]}, {args.jobs} jobs, {elapsed} s.", "",
             "| Failed object | Compiler said |", "|---|---|"]
    for unit in failed:
        said = [line for line in unit.get("stderr", "").splitlines() if " error " in line]
        lines.append(f"| {unit['object']} | {said[-1] if said else unit.get('note', '')} |")
    if implicit is None:
        lines += ["", "Implicit-declaration lint: skipped (no host gcc)."]
    else:
        lines += ["", f"Implicit-declaration lint: {sum(len(v) for v in implicit.values())} found"
                  + "".join(f"; {name}: {', '.join(v)}" for name, v in sorted(implicit.items()))]
    if args.link:
        lines += ["", f"cc1 link: {'linked, ' + str(summary['cc1']['bytes']) + ' bytes' if summary['cc1'] else 'not linked (see make.log)'}"]
    (out / "census.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if not failed and not implicit and (not args.link or summary["cc1"]) else 1


if __name__ == "__main__":
    sys.exit(main())
