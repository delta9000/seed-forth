#!/usr/bin/env python3
"""Build original genmodes through a selected original-member Forth archive.

Both arguments are retained original configure.py work directories. Configuration
and full-byte output audit remain separate acceptance requirements. The sole
source adaptation is the recorded C_alloca frame-depth target branch.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def configured(work, component):
    report = json.loads((work / "report.json").read_text())
    assert report["component"] == component and report["returncode"] == 0
    command = json.loads((work / "configure-command.json").read_text())
    environment = os.environ.copy()
    environment.update(command["environment"])
    hashes = json.loads((work / "toolchain-inputs.json").read_text())
    for name, expected in hashes.items():
        assert sha(work / "toolchain" / name) == expected, name
    return Path(command["command"][1]).parent.parent, environment, hashes


def run(command, cwd, environment, log):
    result = subprocess.run(command, cwd=cwd, env=environment, capture_output=True, timeout=120)
    log.write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0, (command, result.returncode, log)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gcc_work", type=Path)
    parser.add_argument("libiberty_work", type=Path)
    args = parser.parse_args()
    work, library = args.gcc_work.resolve(), args.libiberty_work.resolve()
    source, environment, compiler = configured(work, "gcc")
    library_source, library_environment, library_compiler = configured(library, "libiberty")
    assert compiler == library_compiler, "compiler source sets differ"
    adapter = json.loads((library / "alloca-adapter.json").read_text())
    assert sha(library_source / "libiberty/alloca.c") == adapter["after_sha256"]
    original = json.loads((work / "gcc-source-inputs.json").read_text())
    assert original["files"] == json.loads((library / "gcc-source-inputs.json").read_text())["files"]
    names = {name for name in original["files"] if name.endswith((".h", ".def"))}
    names.update("gcc/" + name for name in ("genmodes.c", "errors.c", "Makefile.in"))
    members = ("alloca", "hashtab", "xmalloc", "xstrdup", "xexit")
    names.update("libiberty/" + name + ".c" for name in members)
    names.add("libiberty/Makefile.in")
    source_inputs = {}
    for name in sorted(names):
        expected = original["files"][name]
        if isinstance(expected, str):
            assert sha(source / name) == expected, name
            source_inputs[name] = expected
    build, libbuild = work / "build/gcc", library / "build/libiberty"
    save(work / "genmodes-source-inputs.json", {"original_sources_headers_definitions": source_inputs,
         "compiler": compiler, "alloca_adapter": adapter})
    objects = " ".join("./" + name + ".o" for name in members)
    archive_command = ["make", "CFLAGS=", "LDFLAGS=", "REQUIRED_OFILES=" + objects,
                       "EXTRA_OFILES=", "LIBOBJS=", "libiberty.a"]
    run(archive_command, libbuild, library_environment, work / "genmodes-archive.log")
    archive = libbuild / "libiberty.a"
    command = ["make", "CFLAGS=", "LDFLAGS=", "BUILD_LIBIBERTY=" + str(archive), "build/genmodes"]
    run(command, build, environment, work / "genmodes-make.log")
    traces = [json.loads(path.read_text()) for path in (work / "probes").glob("*/invocation.json")]
    compiles = [t for t in traces if "-c" in t["arguments"] and t["returncode"] == 0
                and any(a.endswith("/genmodes.c") for a in t["arguments"])]
    assert compiles and all("-DGENERATOR_FILE" in t["arguments"] for t in compiles)
    compile_args = compiles[-1]["arguments"]
    preprocess = []
    skip = False
    for arg in compile_args:
        if skip:
            skip = False
        elif arg == "-o":
            skip = True
        elif arg != "-c":
            preprocess.append(arg)
    driver = work / "toolchain/tools/gcc-direct-cc.py"
    result = run([driver, "-E", *preprocess], Path(compiles[-1]["cwd"]), environment, work / "genmodes.i")
    text = result.stdout.decode()
    target = source / "gcc/config/i386/i386-modes.def"
    target_text = re.sub(r"/\*.*?\*/", "", target.read_text(), flags=re.S)
    target_codes = re.findall(r"\bCC_MODE\s*\(\s*(\w+)\s*\)", target_text)
    target_markers = ["ieee_extended_intel_96_format", "ieee_quad_format", "TARGET_128BIT_LONG_DOUBLE",
                      "TARGET_96_ROUND_53_LONG_DOUBLE", *target_codes]
    assert target_codes == ["CCGC", "CCGOC", "CCNO", "CCZ", "CCFP", "CCFPU"]
    assert all(re.search(r"\b" + marker + r"\b", text) for marker in target_markers), "target computed include missing"
    output = {}
    executable = build / "build/genmodes"
    for filename, options in (("insn-modes.h", ["-h"]), ("min-insn-modes.c", ["-m"]), ("insn-modes.c", [])):
        result = subprocess.run([executable, *options], capture_output=True, timeout=30)
        (work / filename).write_bytes(result.stdout)
        (work / (filename + ".stderr")).write_bytes(result.stderr)
        assert result.returncode == 0 and not result.stderr, (filename, result)
        output[filename] = {"sha256": sha(work / filename), "bytes": len(result.stdout), "returncode": result.returncode}
    header = (work / "insn-modes.h").read_text()
    assert all(re.search(r"\b" + name + r"mode\b", header) for name in ["XF", "TF", *target_codes])
    inputs = {"original_sources_headers_definitions": source_inputs, "compiler": compiler,
              "generated_gcc_headers": {str(p.relative_to(build)): sha(p) for p in build.rglob("*.h") if p.is_file()},
              "generated_libiberty_headers": {str(p.relative_to(libbuild)): sha(p) for p in libbuild.rglob("*.h") if p.is_file()},
              "alloca_adapter": adapter}
    save(work / "genmodes-inputs.json", inputs)
    report = {"scope": "Original genmodes/errors with selected original-member BUILD_LIBIBERTY archive and explicit C_alloca target adapter",
              "configuration": "provisional until independent probe audit", "output_acceptance": "pending independent full-byte oracle",
              "archive_command": archive_command, "generator_command": command,
              "archive_members": list(members), "archive_sha256": sha(archive),
              "archive_objects": {n: sha(libbuild / (n + ".o")) for n in members},
              "generator_objects": {n: sha(build / "build" / (n + ".o")) for n in ("genmodes", "errors")},
              "executable_sha256": sha(executable), "preprocessed_sha256": sha(work / "genmodes.i"),
              "target_definition": {"path": "gcc/config/i386/i386-modes.def", "sha256": sha(target), "markers_consumed": target_markers},
              "output": output, "full_libiberty_build": False, "host_target_tools_used": False}
    save(work / "genmodes-report.json", report)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
