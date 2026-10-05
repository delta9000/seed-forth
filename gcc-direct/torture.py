#!/usr/bin/env python3
"""Run pinned GCC 4.0.4 execute tests with a Forth-built cc1.

Host gcc assembles/links test assembly ONLY as an oracle. No oracle output
is used to build cc1 or any route artifact. All writes stay under --out.
"""
from pathlib import Path
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import fnmatch
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def active_script(text):
    """Ignore blank lines and full-line comments, including commented hooks."""
    return "\n".join(line.rstrip() for line in text.splitlines()
                     if line.strip() and not line.lstrip().startswith("#"))


def evaluate_x(name, script, target, option, inventory):
    """Exact-script evaluator, not Tcl: validate the ENTIRE active script first.

    torture-x.json lists all 25 supported scripts verbatim (minus comments).
    Semantics below cover return 0/1, negated/OR istarget globs, expr return,
    additional_flags, option string-match/continue, and conditional compile/run
    XFAIL hooks. There are no compile-only markers in this pinned execute suite.
    New scripts/markers require explicit implementation; even unreachable
    unknown statements fail validation. The malformed 931004-12.x condition
    raises a Tcl error caught by c-torture.exp, leaving the test enabled.
    """
    if name not in inventory or active_script(script) != inventory[name]:
        raise ValueError(f"unrecognised .x script: {name}; update the explicit evaluator")
    result = {"flags": [], "skip": None, "compile_xfail": None, "run_xfail": None}

    def target_is(*patterns):
        return any(fnmatch.fnmatchcase(target, p) for p in patterns)

    def conditional(stage, reason, targets, includes, excludes):
        # DejaGnu conditional XFAIL lists: any include group, no exclude group.
        # A nested group means all its flags must occur (Thumb + -O0).
        flags = shlex.split(option)
        def matches(group):
            return all(any(fnmatch.fnmatchcase(flag, pattern) for flag in flags)
                       for pattern in group)
        if target_is(*targets) and any(matches(g) for g in includes) and not any(matches(g) for g in excludes):
            result[stage + "_xfail"] = reason

    if name in ("20020404-1.x", "20021024-1.x", "shiftdi.x") and target_is("xstormy16-*"):
        result["skip"] = "16-bit int target"
    if name in ("920501-8.x", "930513-1.x", "980709-1.x", "990826-0.x", "920710-1.x"):
        patterns = ("h8300-*-*",) if name == "920710-1.x" else ("m6811-*-*", "m6812-*-*")
        if target_is(*patterns):
            result["skip"] = "target lacks required long long or libc function"
    if name in ("20010724-1.x", "20040208-2.x"):
        pattern = "mips*-sgi-irix6*" if name == "20010724-1.x" else "mips*-*-irix6*"
        if not target_is(pattern):
            result["skip"] = f"IRIX-only: target does not match {pattern}"
    if name == "20030125-1.x" and not target_is("*linux*"):
        result["skip"] = "requires Linux C99 library functions"
    if name == "990413-2.x" and not target_is("i?86-*-*", "x86_64-*-*"):
        result["skip"] = "x86-only test"
    if name == "20010122-1.x" and "-fomit-frame-pointer" in option:
        result["skip"] = "return_address test excludes -fomit-frame-pointer"
    if name == "20010129-1.x" and target_is("i?86-*-*") and "-m64" not in shlex.split(option):
        result["flags"] = ["-mtune=i686"]
    if name == "20021127-1.x":
        result["flags"] = ["-std=c99"]
    if name == "eeprof-1.x":
        result["flags"] = ["-finstrument-functions"]
        if target_is("powerpc-ibm-aix*"):
            result["run_xfail"] = "eeprof-1.x: powerpc-ibm-aix*"
    if name == "va-arg-25.x" and target_is("i?86-*-*", "x86_64-*-*"):
        result["flags"] = ["-mpreferred-stack-boundary=4"]
    if name == "bf64-1.x" and target_is("mcore-*-*"):
        result["run_xfail"] = "MCore ABI limits bitfields to 32 bits"
    if name == "cvt-1.x" and target_is("d10v-*-*") and "-mint32" not in option:
        result["run_xfail"] = "d10v int is not 32 bits"
    if name == "20020720-1.x":
        if target_is("sparc*-*-*"):
            conditional("compile", "PR opt/10348", ["*-*-*"], [["-fpic"], ["-fPIC"]], [["-O0"]])
        else:
            conditional("compile", "incomplete floating point optimisation",
                        ["xtensa-*-*", "sh-*-*", "arm*-*-*", "strongarm*-*-*", "xscale*-*-*",
                         "h8300*-*-*", "frv-*-*", "powerpc-*-*spe"], [["*"]], [["-O0"]])
    if name == "941014-1.x":
        conditional("run", "Thumb function relocations set the last bit",
                    ["arm*-*-*", "xscale*-*-*", "strongarm*-*-*"], [["-mthumb", "-O0"]], [[""]])
    if name in ("980709-1.x", "990826-0.x") and target_is("powerpc-*-aix*", "rs6000-*-aix*"):
        conditional("run", "system libm ABI with -msoft-float", ["*-*-aix*"], [["-msoft-float"]], [[""]])
    if name == "981130-1.x":
        conditional("run", "alias analysis conflicts with instruction scheduling", ["m32r-*-*"],
                    [["-O2"], ["-O1"], ["-O0"], ["-Os"]], [[""]])
    # 960312-1.x sets `options`, but c-torture-execute resets it before compile.
    # 930529-1.x has only return 0; its XFAIL hook is entirely commented out.
    if name == "931004-12.x":
        result["note"] = "malformed Tcl target quote; c-torture.exp catches error and runs normally"
    return result


def headers(build, source, out, jobs, record):
    """Copy configured inputs; never invoke make inside the supplied tree."""
    private = out / "header-build"
    private.mkdir()
    for path in build.iterdir():
        if path.is_file() and path.suffix not in (".o", ".a") and path.name not in ("cc1", "stmp-int-hdrs", "xlimits.h"):
            shutil.copy2(path, private / path.name)
    environment = os.environ.copy()
    environment.update(record["environment"])
    environment["LC_ALL"] = "C"
    # Retain configured facts, not configure's absolute source location. Prevent
    # copied config.status from rerunning configure (and writing old probe paths).
    command = ["make", "-j", str(jobs), "-o", "Makefile", "-o", "config.status",
               "CFLAGS=", "LDFLAGS=", "STMP_FIXINC=", f"srcdir={source / 'gcc'}",
               f"VPATH={source / 'gcc'}", "stmp-int-hdrs"]
    with (out / "int-hdrs.log").open("wb") as log:
        result = subprocess.run(command, cwd=private, env=environment, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"private header make failed ({result.returncode}); see {out / 'int-hdrs.log'}")
    # stmp-fixinc's fallback when no fixed system limits.h exists. Skipping
    # fixincludes skips this copy too; xlimits.h still includes <syslimits.h>.
    shutil.copyfile(source / "gcc/gsyslimits.h", private / "include/syslimits.h")
    (private / "include/syslimits.h").chmod(0o644)
    return private / "include", {"command": command, "cwd": str(private), "returncode": result.returncode,
                                 "syslimits_sha256": sha(private / "include/syslimits.h")}


def run(command, cwd, log, timeout):
    # GNU timeout, as in the scratch script, bounds children as well as cc1.
    with log.open("wb") as stream:
        result = subprocess.run(["timeout", "--kill-after=5", str(timeout), *command], cwd=cwd,
                                env=dict(os.environ, LC_ALL="C"), stdout=stream, stderr=subprocess.STDOUT)
    return {"command": command, "returncode": result.returncode, "timeout_seconds": timeout, "log": str(log)}


def test_one(source, option, policy, cc1, include, oracle, out, extra):
    directory = out / option.replace(" ", "_") / source.stem
    directory.mkdir(parents=True)
    result = {"test": source.name, "option": option, "source_sha256": sha(source), "policy": policy, "steps": []}
    if policy["skip"]:
        return dict(result, status="SKIP", reason=policy["skip"])
    assembly = directory / "t.s"
    executable = directory / "t"
    commands = [
        ("cc1", ["prlimit", "--as=4096000000", "--", str(cc1), "-quiet", "-w", *shlex.split(option),
                 "-fno-builtin-abort", "-isystem", str(include), "-isystem", "/usr/include/x86_64-linux-gnu",
                 *extra, *policy["flags"], str(source), "-o", str(assembly)], "cc1.err", 120),
        ("link", [oracle, "-no-pie", "-w", str(assembly), "-o", str(executable), "-lm"], "ld.err", 120),
        ("run", [str(executable)], "out", 20),
    ]
    for stage, command, log, timeout in commands:
        step = run(command, directory, directory / log, timeout)
        result["steps"].append(dict(step, stage=stage))
        expected = policy["run_xfail" if stage == "run" else "compile_xfail"]
        if step["returncode"]:
            return dict(result, status="XFAIL" if expected else f"FAIL({stage})",
                        reason=expected or f"exit {step['returncode']}", failed_stage=stage)
        if expected and stage in ("link", "run"):
            return dict(result, status=f"FAIL({stage})", reason=f"XPASS: {expected}", failed_stage=stage)
    return dict(result, status="PASS", reason="")


def reports(out, report):
    counts = Counter(r["status"] for r in report["results"])
    report["counts"] = dict(sorted(counts.items()))
    (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    lines = ["# GCC 4.0.4 execute torture", "", report["scope"], "",
             f"Target: {report.get('target', 'unknown')}; jobs: {report['jobs']}.", "",
             "; ".join(f"{status}: {count}" for status, count in sorted(counts.items())), "",
             "| Option | Test | Result | Reason |", "|---|---|---|---|"]
    for result in report["results"]:
        lines.append(f"| {result['option']} | {result['test']} | {result['status']} | {result['reason'].replace('|', '/')} |")
    lines += ["", "## .x inventory", ""]
    for entry in report["x_files"]:
        lines.append(f"- {entry['name']}: {entry.get('error', entry.get('note', 'recognised'))}")
    if report.get("error"):
        lines += ["", "Setup failed: " + report["error"]]
    (out / "report.md").write_text("\n".join(lines) + "\n")
    print("; ".join(f"{status}: {count}" for status, count in sorted(counts.items())), flush=True)
    print(f"Reports: {out / 'report.json'}, {out / 'report.md'}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cc1", type=Path)
    parser.add_argument("build", type=Path, help="configured GCC build/gcc directory (read only)")
    parser.add_argument("--source", type=Path, default=ROOT / "build-out/direct-gcc-inputs/gcc-source")
    parser.add_argument("--out", type=Path, default=ROOT / "build-out/torture")
    parser.add_argument("--levels", default="-O0 -O2", help="space-separated optimisation levels; use --levels='-O0 -O2'")
    parser.add_argument("--extra", default=os.environ.get("EXTRA", ""), help="extra cc1 flags (scratch script's EXTRA)")
    parser.add_argument("--configure-record", type=Path, help="default: BUILD/../../configure-command.json")
    parser.add_argument("-j", "--jobs", type=int, default=6)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 6:
        parser.error("jobs must be between 1 and 6 (5 GB memory limit)")
    options = args.levels.split()
    if not options or any(not re.fullmatch(r"-O(?:[0-3sg]|fast)", option) for option in options) or len(set(options)) != len(options):
        parser.error("levels must be unique -O optimisation flags")
    cc1, build, source, out = (p.resolve() for p in (args.cc1, args.build, args.source, args.out))
    if not out.is_relative_to(ROOT / "build-out") or out == ROOT / "build-out":
        parser.error("out must be a new directory under this worktree's build-out")
    if any(out == p or out.is_relative_to(p) or p.is_relative_to(out) for p in (build, source, cc1)):
        parser.error("output must not overlap the inputs")
    if out.exists():
        parser.error("output already exists; use a fresh --out for each repeat")
    out.mkdir(parents=True)
    report = {"scope": "Forth-built cc1 compiles tests; host gcc assembly/link and host execution are oracle-only. No route artifacts are produced.",
              "cc1": str(cc1), "build": str(build), "source": str(source), "jobs": args.jobs,
              "levels": options, "extra": shlex.split(args.extra), "results": [], "x_files": []}
    started = time.time()
    try:
        oracle = shutil.which("gcc")
        if not oracle:
            raise RuntimeError("host gcc oracle is unavailable")
        for tool in ("timeout", "prlimit", "make"):
            if not shutil.which(tool):
                raise RuntimeError(f"required tool unavailable: {tool}")
        record_path = args.configure_record or build.parent.parent / "configure-command.json"
        record = json.loads(record_path.read_text())
        target = re.search(r"^target\s*=\s*(\S+)", (build / "Makefile").read_text(), re.MULTILINE).group(1)
        if target != "x86_64-pc-linux-gnu":
            raise RuntimeError(f"native oracle runner supports x86_64-pc-linux-gnu, got {target}")
        report.update(target=target, cc1_sha256=sha(cc1), configure_record=str(record_path), configure=record,
                      oracle=oracle, oracle_version=subprocess.run([oracle, "--version"], capture_output=True, text=True, check=True).stdout.splitlines()[0])
        suite = source / "gcc/testsuite/gcc.c-torture/execute"
        tests = sorted(suite.glob("*.c"))
        if not tests:
            raise RuntimeError(f"no execute tests found in {suite}")
        inventory = json.loads(Path(__file__).with_name("torture-x.json").read_text())
        scripts = {}
        errors = {}
        for path in sorted(suite.glob("*.x")):
            script = path.read_text()
            entry = {"name": path.name, "sha256": sha(path)}
            try:
                policy = evaluate_x(path.name, script, target, options[0], inventory)
                if "note" in policy:
                    entry["note"] = policy["note"]
                scripts[path.stem] = script
            except ValueError as error:
                entry["error"] = str(error)
                errors[path.stem] = str(error)
            report["x_files"].append(entry)
        if errors:
            for name, error in errors.items():
                report["results"].append({"test": name + ".x", "option": "all", "status": "FAIL(cc1)", "reason": error})
            raise RuntimeError("unrecognised .x directives; tests were not run")
        include, step = headers(build, source, out, args.jobs, record)
        report["headers"] = step
        tasks = [(test, option) for option in options for test in tests]
        print(f"{len(tests)} tests x {len(options)} levels; {len(scripts)} .x files; {args.jobs} jobs", flush=True)
        def one(task):
            test, option = task
            policy = evaluate_x(test.stem + ".x", scripts[test.stem], target, option, inventory) if test.stem in scripts else {"flags": [], "skip": None, "compile_xfail": None, "run_xfail": None}
            return test_one(test, option, policy, cc1, include, oracle, out, report["extra"])
        with ThreadPoolExecutor(args.jobs) as pool:
            report["results"] = list(pool.map(one, tasks))
        (out / "results.txt").write_text("".join(f"{r['option']} {Path(r['test']).stem} {r['status']} {r['reason']}\n" for r in report["results"]))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, AttributeError) as error:
        report["error"] = str(error)
        print(f"torture: {error}", file=sys.stderr)
    report["seconds"] = round(time.time() - started, 1)
    reports(out, report)
    return 1 if report.get("error") or any(r["status"].startswith("FAIL") for r in report["results"]) else 0


if __name__ == "__main__":
    sys.exit(main())
