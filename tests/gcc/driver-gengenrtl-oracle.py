#!/usr/bin/env python3
"""Optional host GCC/libc oracle; no oracle artifact enters production."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path, help="retained work directory already checked by driver-gengenrtl-check.py")
    args = parser.parse_args()
    work = args.work.resolve()
    production = json.loads((work / "gengenrtl-report.json").read_text())
    inputs = json.loads((work / "gengenrtl-inputs.json").read_text())
    configuration = json.loads((work / "configure-command.json").read_text())
    source = Path(configuration["command"][1]).parent.parent
    build = work / "build/gcc"
    for name, expected in inputs["original_header_definition_and_source_sha256"].items():
        assert sha(source / name) == expected, "original input changed: " + name
    for name, expected in inputs["generated_header_sha256"].items():
        assert sha(build / name) == expected, "generated configuration changed: " + name
    compiler = shutil.which("gcc")
    if not compiler:
        print("SKIP: optional independent oracle requires host GCC")
        return 77
    oracle = work / "host-oracle"
    oracle.mkdir(exist_ok=True)
    # C90 avoids exposing host POSIX declarations which the audited bounded
    # runtime correctly reports absent (notably GCC4's strsignal fallback).
    command = [compiler, "-std=c90", "-O0", "-DGENERATOR_FILE", "-DHAVE_CONFIG_H", "-DIN_GCC",
               "-I" + str(build), "-I" + str(source / "gcc"), "-I" + str(source / "include"),
               "-I" + str(source / "libcpp/include"), str(source / "gcc/gengenrtl.c"),
               str(source / "gcc/errors.c"), "-o", str(oracle / "gengenrtl")]
    result = subprocess.run(command, capture_output=True)
    (oracle / "compile-c90.log").write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    report = {"purpose": "Independent host GCC/libc output oracle only; no host artifact is consumed by production",
              "command": command, "compile_returncode": result.returncode, "compiler": compiler,
              "version": subprocess.check_output([compiler, "--version"]).decode().splitlines()[0],
              "branch_facts": production["branch_facts"], "configuration_sha256": sha(build / "auto-host.h"),
              "dialect": "C90; original source and configuration headers are unchanged"}
    for name, options in (("genrtl.c", []), ("genrtl.h", ["-h"])):
        result = subprocess.run([oracle / "gengenrtl", *options], capture_output=True,
                                env={**os.environ, "LC_ALL": "C"}, timeout=30)
        assert result.returncode == 0 and not result.stderr, result
        (oracle / name).write_bytes(result.stdout)
        assert sha(work / name) == production["output"][name]["sha256"], "production output changed"
        matched = result.stdout == (work / name).read_bytes()
        report[name] = {"exit": result.returncode, "bytes": len(result.stdout),
                        "sha256": sha(oracle / name), "equals_forth_production": matched}
        assert matched, "host oracle differs: " + name
    (oracle / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("PASS: complete original gengenrtl C/header outputs equal independent host GCC/libc oracle")
    print(oracle / "report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
