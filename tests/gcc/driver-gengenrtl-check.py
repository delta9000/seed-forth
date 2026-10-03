#!/usr/bin/env python3
"""Build original gengenrtl using a retained configure.py source snapshot.

The output coverage oracle reads original rtl.def independently, selecting
only its two documented conditional symbols from audited configuration and
the actual GENERATOR_FILE compile option. It never produces target files.
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


def original_definitions(text, facts):
    # Deliberately narrow verification grammar: refuse any new directive
    # rather than accidentally treating an unknown branch as active.
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    selected, conditions = [], []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            directive = line.strip().split()
            if directive[0] == "#ifdef" and len(directive) == 2 and directive[1] in facts:
                conditions.append(facts[directive[1]])
            elif directive == ["#else"] and conditions:
                conditions[-1] = not conditions[-1]
            elif directive == ["#endif"] and conditions:
                conditions.pop()
            else:
                raise AssertionError("unrecognized oracle directive: " + line)
        elif all(conditions):
            selected.append(line)
    assert not conditions
    active = "\n".join(selected)
    entries = re.findall(r'\bDEF_RTL_EXPR\s*\(\s*(\w+)\s*,\s*"([^"]*)"\s*,\s*("[^"]*"|CONST_DOUBLE_FORMAT)\s*,\s*\w+\s*\)', active)
    assert len(entries) == len(re.findall(r"\bDEF_RTL_EXPR\s*\(", active)), "unparsed original RTL entry"
    assert len(entries) == len({name for name, _, _ in entries}), "duplicate selected RTL name"
    return [(name, "" if fmt == "CONST_DOUBLE_FORMAT" else fmt[1:-1]) for name, _, fmt in entries]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path, help="retained configure.py work directory")
    args = parser.parse_args()
    work = args.work.resolve()
    configuration = json.loads((work / "report.json").read_text())
    assert configuration["component"] == "gcc" and configuration["returncode"] == 0
    invocation = json.loads((work / "configure-command.json").read_text())
    source = Path(invocation["command"][1]).parent.parent
    build = work / "build/gcc"
    environment = os.environ.copy()
    environment.update(invocation["environment"])
    original_hashes = json.loads((work / "gcc-source-inputs.json").read_text())["files"]
    source_inputs = {}
    # Retain/check all original headers and .def files, a conservative superset
    # of those consumed, plus the concrete original source/build files.
    for name, expected in original_hashes.items():
        if name.endswith((".h", ".def")) or name in ("gcc/gengenrtl.c", "gcc/errors.c", "gcc/Makefile.in"):
            if isinstance(expected, str):
                actual = sha(source / name)
                assert actual == expected, "original source changed: " + name
                source_inputs[name] = actual
    toolchain_hashes = json.loads((work / "toolchain-inputs.json").read_text())
    for name, expected in toolchain_hashes.items():
        assert sha(work / "toolchain" / name) == expected, "frozen toolchain changed: " + name
    command = ["make", "CFLAGS=", "LDFLAGS=", "build/gengenrtl.o", "build/errors.o"]
    result = subprocess.run(command, cwd=build, env=environment, capture_output=True)
    (work / "gengenrtl-make.log").write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    generated = {str(path.relative_to(build)): sha(path) for path in build.rglob("*.h") if path.is_file()}
    inputs = {"original_header_definition_and_source_sha256": source_inputs,
              "generated_header_sha256": generated, "frozen_toolchain_sha256": toolchain_hashes}
    save(work / "gengenrtl-inputs.json", inputs)
    driver = work / "toolchain/tools/gcc-direct-cc.py"
    wrapper = work / "toolchain/gcc-direct/configure.py"
    executable = build / "build/gengenrtl-direct"
    command = [sys.executable, str(wrapper), "--invoke", str(driver), str(work / "probes"),
               "build/gengenrtl.o", "build/errors.o", "-o", str(executable)]
    result = subprocess.run(command, cwd=build, env=environment, capture_output=True)
    (work / "gengenrtl-link.log").write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    runs = {}
    for name, options in (("genrtl.c", []), ("genrtl.h", ["-h"])):
        result = subprocess.run([executable, *options], capture_output=True, timeout=30)
        assert result.returncode == 0 and not result.stderr, result
        (work / name).write_bytes(result.stdout)
        runs[name] = {"returncode": result.returncode, "bytes": len(result.stdout), "sha256": sha(work / name)}
    auto_host = re.sub(r"/\*.*?\*/", "", (build / "auto-host.h").read_text(), flags=re.S)
    facts = {"USE_MAPPED_LOCATION": bool(re.search(r"^\s*#\s*define\s+USE_MAPPED_LOCATION\b", auto_host, re.M)),
             "GENERATOR_FILE": True}
    traces = [json.loads(path.read_text()) for path in (work / "probes").glob("*/invocation.json")]
    compilation = [trace for trace in traces if "-c" in trace["arguments"]
                   and any(arg.endswith("/gengenrtl.c") for arg in trace["arguments"])
                   and trace["returncode"] == 0]
    assert compilation and all("-DGENERATOR_FILE" in trace["arguments"] for trace in compilation)
    assert all(not any(arg.startswith(("-DUSE_MAPPED_LOCATION", "-UUSE_MAPPED_LOCATION"))
                       for arg in trace["arguments"]) for trace in compilation)
    assert re.search(r'^#define CONST_DOUBLE_FORMAT\s+""\s*$', (source / "gcc/gengenrtl.c").read_text(), re.M)
    entries = original_definitions((source / "gcc/rtl.def").read_text(), facts)
    usable = [(name, fmt) for name, fmt in entries if not any(letter in fmt for letter in "*VSn")]
    formats = list(dict.fromkeys(fmt for _, fmt in usable))
    expected_macros = [("raw_" if name in ("CONST_INT", "REG", "SUBREG", "MEM", "CONST_VECTOR") else "") + name
                       for name, _ in usable if name != "CONST_DOUBLE"]
    actual_definitions = re.findall(r"^gen_rtx_fmt_(\w*) \(", (work / "genrtl.c").read_text(), re.M)
    actual_declarations = re.findall(r"^extern rtx gen_rtx_fmt_(\w*)\s+\(", (work / "genrtl.h").read_text(), re.M)
    actual_macros = re.findall(r"^#define gen_rtx_(\w+)\(", (work / "genrtl.h").read_text(), re.M)
    assert actual_definitions == formats and actual_declarations == formats
    assert actual_macros == expected_macros
    report = {"configuration": "bounded configure acceptance is separate from this generator coverage check",
              "link_scope": "original gengenrtl.o + errors.o + bounded runtime; BUILD_LIBIBERTY omitted",
              "branch_facts": facts, "rtl_definition_count": len(entries), "supported_format_count": len(formats),
              "generated_macro_count": len(actual_macros), "output": runs,
              "coverage_oracle": "independent original rtl.def reader using audited auto-host and actual compile flags",
              "coverage_is_full_byte_oracle": False, "ordered_definitions_declarations_macros_match": True,
              "original_input_hash_count": len(source_inputs), "input_manifest": "gengenrtl-inputs.json",
              "object_sha256": {name: sha(build / "build" / name) for name in ("gengenrtl.o", "errors.o")},
              "executable_sha256": sha(executable), "host_target_tools_used": False,
              "initial_inventory_correction": "The first raw regex inventory counted both USE_MAPPED_LOCATION branches. That was a harness error, not a compiler failure."}
    save(work / "gengenrtl-report.json", report)
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
