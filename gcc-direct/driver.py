#!/usr/bin/env python3
"""Build the GCC 4.0.4 driver toolchain (gcc, cpp, cc1, collect2) on our binutils.

Usage:
    python3 gcc-direct/driver.py WORK --binutils BINUTILS_WORK \\
        --oyacc OYACC --flex FLEX [-j JOBS]

BINUTILS_WORK is a finished gcc-direct/binutils.py run.  Its as-new, ld-new
(required) and ar, nm-new, objdump, readelf (when built) are checked against
its stage-B report and copied into WORK/toolchain as as, ld, ar, nm, objdump,
readelf.  Then, in order, with the frozen Forth toolchain:

1. configure.py --forth-ar runs the original configure scripts into
   WORK/libiberty (with --alloca-frame), WORK/libcpp and WORK/gcc.  GCC gets
   --with-binutils WORK/toolchain, so its assembler/linker probes run our
   as/ld and the driver records WORK/toolchain/as and WORK/toolchain/ld as
   DEFAULT_ASSEMBLER/DEFAULT_LINKER.  configure needs them to exist, which is
   why they are installed first.
2. census.py --link builds libiberty.a, every cc1 object, libcpp.a and cc1
   with the original Makefiles (WORK/census/).
3. The same GCC Makefile, with census.py's overrides, builds xgcc, cpp and
   collect2.
4. xgcc (as gcc), cpp, cc1 and collect2 are copied into WORK/toolchain.

The layout is flat and is used with -BWORK/toolchain/.  The GCC 4.0.4 driver
looks for cc1 and collect2 in each -B prefix (first under
x86_64-pc-linux-gnu/4.0.4/ inside it, then the prefix itself); without -B it
would look under its configured install prefix instead.  as and ld are not
searched for: gcc.c and collect2.c run DEFAULT_ASSEMBLER/DEFAULT_LINKER
whenever those absolute paths are executable, ahead of -B and PATH.  The
toolchain is therefore tied to its WORK path.

5. tests/gcc/e2e-freestanding-check.py builds and runs a freestanding program
   with one driver command under `env -i PATH=WORK/toolchain`
   (results in WORK/e2e/).

WORK/report.json and report.md record every step, the input binutils hashes,
the installed tool hashes, guard-log counts and the end-to-end result.  WORK
must be new.  Host compilers and binutils never produce a toolchain file.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "gcc-direct"))
import census  # noqa: E402  (shared make helpers and overrides)

# binutils.py build path -> installed name; as and ld are required.
BINUTILS = {"gas/as-new": "as", "ld/ld-new": "ld", "binutils/ar": "ar",
            "binutils/nm-new": "nm", "binutils/objdump": "objdump", "binutils/readelf": "readelf"}
# GCC build path -> installed name.
DRIVER = {"xgcc": "gcc", "cpp": "cpp", "cc1": "cc1", "collect2": "collect2"}
CONFIGURE = {"libiberty": ["--forth-ar", "--alloca-frame"], "libcpp": ["--forth-ar"],
             "gcc": ["--forth-ar"]}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, log, cwd=ROOT, environment=None):
    started = time.time()
    with log.open("wb") as stream:
        result = subprocess.run(command, cwd=cwd, env=environment, stdout=stream, stderr=subprocess.STDOUT)
    return {"command": command, "returncode": result.returncode,
            "seconds": round(time.time() - started, 1), "log": str(log)}


def install_binutils(source, tools):
    report = json.loads((source / "stage-b/report.json").read_text())
    recorded = {tool["path"]: tool.get("sha256") for tool in report["tools"]}
    installed = {}
    for path, name in BINUTILS.items():
        built = source / "build/top" / path
        if not built.is_file():
            if name in ("as", "ld"):
                raise RuntimeError(f"binutils run lacks {path}")
            continue
        digest = sha(built)
        if recorded.get(path) != digest:
            raise RuntimeError(f"{path} differs from {source}/stage-b/report.json")
        shutil.copyfile(built, tools / name)
        (tools / name).chmod(0o755)
        installed[name] = {"from": str(built), "sha256": digest, "bytes": built.stat().st_size}
    return installed


def guard_attempts(work):
    log = work / "host-tool-attempts.jsonl"
    counts = {}
    for line in log.read_text().splitlines() if log.is_file() else []:
        tool = json.loads(line)["tool"]
        counts[tool] = counts.get(tool, 0) + 1
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("work", type=Path, help="new work directory")
    parser.add_argument("--binutils", type=Path, required=True, help="finished gcc-direct/binutils.py WORK")
    parser.add_argument("--oyacc", type=Path, required=True, help="Forth-built oyacc executable")
    parser.add_argument("--flex", type=Path, required=True, help="Forth-built flex executable")
    parser.add_argument("-j", "--jobs", type=int, default=6, help="parallel make jobs (1-8, default 6)")
    args = parser.parse_args()
    if not 1 <= args.jobs <= 8:
        parser.error("jobs must be 1-8 (each Forth compile can use a few hundred MiB)")
    for name in ("oyacc", "flex"):
        path = getattr(args, name).resolve()
        if not path.is_file() or not os.access(path, os.X_OK):
            parser.error(f"--{name} must name an executable file: {path}")
        setattr(args, name, path)
    binutils = args.binutils.resolve()
    if not (binutils / "stage-b/report.json").is_file():
        parser.error(f"--binutils must be a finished binutils.py run: {binutils}")
    work = args.work.resolve()
    if work.exists():
        parser.error(f"work directory already exists: {work}")
    tools = work / "toolchain"
    tools.mkdir(parents=True)
    logs = work / "logs"
    logs.mkdir()
    summary = {"scope": "GCC 4.0.4 driver toolchain on Forth-built binutils; configure answers provisional",
               "binutils_work": str(binutils), "binutils_report_sha256": sha(binutils / "stage-b/report.json"),
               "oyacc_sha256": sha(args.oyacc), "flex_sha256": sha(args.flex), "jobs": args.jobs,
               "layout": "flat; use -B" + str(tools) + "/ (as/ld via DEFAULT_ASSEMBLER/DEFAULT_LINKER)",
               "binutils": install_binutils(binutils, tools), "steps": []}
    steps = summary["steps"]
    print(f"Installed binutils into {tools}", flush=True)

    # The three configure scripts are independent; run them side by side.
    running = []
    for component, options in CONFIGURE.items():
        if component == "gcc":
            options = [*options, "--with-binutils", str(tools)]
        command = [sys.executable, str(ROOT / "gcc-direct/configure.py"), "--component", component,
                   *options, "--work", str(work / component)]
        log = logs / f"configure-{component}.log"
        running.append((component, command, log, time.time(),
                        subprocess.Popen(command, cwd=ROOT, stdout=log.open("wb"), stderr=subprocess.STDOUT)))
    for component, command, log, started, process in running:
        steps.append({"command": command, "returncode": process.wait(),
                      "seconds": round(time.time() - started, 1), "log": str(log)})
        print(f"configure {component}: exit {steps[-1]['returncode']}", flush=True)
    configured = all(step["returncode"] == 0 for step in steps)

    if configured:
        print(f"census.py --link with {args.jobs} jobs; log: {logs / 'census.log'}", flush=True)
        steps.append(run([sys.executable, str(ROOT / "gcc-direct/census.py"), str(work),
                          "--oyacc", str(args.oyacc), "--flex", str(args.flex),
                          "-j", str(args.jobs), "--link"], logs / "census.log"))
        print(f"census: exit {steps[-1]['returncode']}", flush=True)
        gcc_build = work / "gcc/build/gcc"
        log = logs / "driver-make.log"
        steps.append(census.make(gcc_build, census.environment_for(work / "gcc"),
                                 ["-j", str(args.jobs), *census.gcc_overrides(work, args.oyacc, args.flex),
                                  "xgcc", "cpp", "collect2"], log))
        steps[-1]["log"] = str(log)
        print(f"make xgcc cpp collect2: exit {steps[-1]['returncode']}", flush=True)
        for built, name in DRIVER.items():
            if (gcc_build / built).is_file():
                shutil.copyfile(gcc_build / built, tools / name)
                (tools / name).chmod(0o755)

    summary["toolchain"] = {p.name: {"sha256": sha(p), "bytes": p.stat().st_size}
                            for p in sorted(tools.iterdir())}
    summary["missing"] = [name for name in (*DRIVER.values(), "as", "ld") if name not in summary["toolchain"]]
    summary["guard_attempts_during_configure"] = {c: guard_attempts(work / c) for c in CONFIGURE}
    auto_host = work / "gcc/build/gcc/auto-host.h"
    if auto_host.is_file():
        summary["auto_host_defaults"] = [line for line in auto_host.read_text().splitlines()
                                         if line.startswith(("#define DEFAULT_ASSEMBLER", "#define DEFAULT_LINKER"))]
    census_json = work / "census/census.json"
    if census_json.is_file():
        record = json.loads(census_json.read_text())
        summary["census"] = {key: record[key] for key in ("objects", "built", "failed", "cc1", "compiler_inputs_sha256")}

    e2e = None
    if not summary["missing"]:
        print("end-to-end check", flush=True)
        steps.append(run([sys.executable, str(ROOT / "tests/gcc/e2e-freestanding-check.py"), str(work),
                          "--out", str(work / "e2e")], logs / "e2e.log"))
        result = work / "e2e/result.json"
        if result.is_file():
            e2e = json.loads(result.read_text())
            summary["e2e"] = {key: e2e.get(key) for key in (
                "command", "build_returncode", "run_stdout", "run_returncode", "hello_sha256",
                "execve_programs", "verbose_commands", "verbose_include_search", "guard_log_unchanged",
                "guard_path_embedded_in", "oracle", "failures")}
    ok = configured and not summary["missing"] and all(s["returncode"] == 0 for s in steps)
    summary["result"] = "pass" if ok else "fail"
    (work / "report.json").write_text(json.dumps(summary, indent=2) + "\n")

    lines = [f"# GCC driver toolchain: {summary['result']}", "", summary["scope"], "",
             f"Toolchain: `{tools}` ({summary['layout']}). Jobs: {args.jobs}.", "", "## Steps", ""]
    for step in steps:
        command = " ".join(Path(c).name if i < 2 else c for i, c in enumerate(step["command"][:4]))
        lines.append(f"- `{command} ...`: exit {step['returncode']}, {step['seconds']} s ({step['log']})")
    lines += ["", "## Installed tools", "", "| Tool | Bytes | SHA256 |", "|---|---|---|"]
    for name, tool in summary["toolchain"].items():
        lines.append(f"| {name} | {tool['bytes']} | {tool['sha256']} |")
    lines += ["", "## Configure", ""] + [f"- `{line}`" for line in summary.get("auto_host_defaults", [])]
    for component, counts in summary["guard_attempts_during_configure"].items():
        lines.append(f"- {component} guard attempts: {counts or 'none'}")
    if "census" in summary:
        c = summary["census"]
        lines.append(f"- cc1 census: {c['built']} of {c['objects']} objects; cc1 "
                     f"{c['cc1']['sha256'] if c['cc1'] else 'not linked'}")
    if e2e:
        lines += ["", "## End to end", "", "```", "$ " + e2e["command"], e2e.get("run_stdout", "") +
                  f"(exit {e2e.get('run_returncode')})", "```", "",
                  "Executed: " + ", ".join(e2e["execve_programs"]) if isinstance(e2e["execve_programs"], list)
                  else "Executed (-v): " + ", ".join(e2e["verbose_commands"]),
                  f"Guard log unchanged: {e2e['guard_log_unchanged']}.",
                  f"Oracle (report only): {e2e['oracle']}."]
        lines += [f"- FAIL: {failure}" for failure in e2e["failures"]]
    (work / "report.md").write_text("\n".join(lines) + "\n")
    print(work / "report.md", flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"driver: {error}", file=sys.stderr)
        sys.exit(1)
