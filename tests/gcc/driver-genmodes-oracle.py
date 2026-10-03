#!/usr/bin/env python3
"""Compare complete original genmodes outputs with an isolated host oracle.

The host path uses the same original generator and library C, generated config
facts and target .def input. Native C_alloca retains its upstream local-address
depth branch. No host artifact enters the Forth production path.
"""
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
    parser.add_argument("gcc_work", type=Path)
    parser.add_argument("libiberty_work", type=Path)
    args = parser.parse_args()
    work, library = args.gcc_work.resolve(), args.libiberty_work.resolve()
    production = json.loads((work / "genmodes-report.json").read_text())
    inputs = json.loads((work / "genmodes-inputs.json").read_text())
    config = json.loads((work / "configure-command.json").read_text())
    source = Path(config["command"][1]).parent.parent
    build, libbuild = work / "build/gcc", library / "build/libiberty"
    for name, expected in inputs["original_sources_headers_definitions"].items():
        assert sha(source / name) == expected, name
    for root, hashes in ((build, inputs["generated_gcc_headers"]), (libbuild, inputs["generated_libiberty_headers"])):
        for name, expected in hashes.items():
            assert sha(root / name) == expected, name
    compiler = shutil.which("gcc")
    if not compiler:
        print("SKIP: independent output oracle requires host GCC")
        return 77
    oracle = work / "genmodes-host-oracle"
    oracle.mkdir(exist_ok=True)
    commands = []
    objects = []
    for name in production["archive_members"]:
        obj = oracle / (name + ".o")
        command = [compiler, "-std=c90", "-O0", "-DHAVE_CONFIG_H", "-I" + str(libbuild),
                   "-I" + str(source / "include"), "-c", str(source / "libiberty" / (name + ".c")), "-o", str(obj)]
        result = subprocess.run(command, capture_output=True)
        (oracle / (name + ".log")).write_bytes(result.stdout + result.stderr)
        assert result.returncode == 0, (name, result.stderr)
        commands.append(command)
        objects.append(obj)
    command = [compiler, "-std=c90", "-O0", "-DGENERATOR_FILE", "-DHAVE_CONFIG_H", "-DIN_GCC",
               "-I" + str(build), "-I" + str(source / "gcc"), "-I" + str(source / "include"),
               "-I" + str(source / "libcpp/include"), str(source / "gcc/genmodes.c"),
               str(source / "gcc/errors.c"), *map(str, objects), "-o", str(oracle / "genmodes")]
    result = subprocess.run(command, capture_output=True)
    (oracle / "link.log").write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0, result.stderr
    commands.append(command)
    report = {"purpose": "Independent host GCC/libc oracle only; host outputs never enter production",
              "commands": commands, "compiler": compiler,
              "version": subprocess.check_output([compiler, "--version"]).decode().splitlines()[0],
              "original_sources_unchanged": True, "native_alloca_branch": "original ADDRESS_FUNCTION(probe)",
              "target_definition": production["target_definition"], "output": {}}
    for name, options in (("insn-modes.h", ["-h"]), ("min-insn-modes.c", ["-m"]), ("insn-modes.c", [])):
        result = subprocess.run([oracle / "genmodes", *options], capture_output=True,
                                env={**os.environ, "LC_ALL": "C"}, timeout=30)
        (oracle / name).write_bytes(result.stdout)
        (oracle / (name + ".stderr")).write_bytes(result.stderr)
        assert result.returncode == 0 and not result.stderr, (name, result)
        assert sha(work / name) == production["output"][name]["sha256"], name
        match = result.stdout == (work / name).read_bytes()
        report["output"][name] = {"sha256": sha(oracle / name), "bytes": len(result.stdout), "equals_forth_production": match}
    (oracle / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    assert all(v["equals_forth_production"] for v in report["output"].values()), "complete host output differs"
    print("PASS: complete original genmodes C/minimal C/header outputs equal independent host GCC/libc oracle")
    print(oracle / "report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
