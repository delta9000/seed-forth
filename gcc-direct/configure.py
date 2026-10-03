#!/usr/bin/env python3
"""Run unmodified pinned GCC configure with a frozen Forth toolchain.

Configuration is provisional: the retained probe sources and outcomes must be
audited before feature answers are treated as compiler/runtime evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = "gcc-4.0.4-git-944765863e.tar"
TRIPLE = "x86_64-pc-linux-gnu"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def invoke(driver, trace_root, arguments):
    """Transparent compiler invocation capture, without changing arguments."""
    trace = Path(tempfile.mkdtemp(prefix=f"{time.time_ns()}-", dir=trace_root))
    inputs = []
    candidates = [Path(arg) for arg in arguments if Path(arg).suffix in (".c", ".h", ".o")]
    candidates += [Path(name) for name in ("confdefs.h", "config.h", "bconfig.h")]
    seen = set()
    for path in candidates:
        if path.is_file() and str(path.absolute()) not in seen:
            data = path.read_bytes()
            name = f"input-{len(inputs)}{path.suffix}"
            (trace / name).write_bytes(data)
            inputs.append({"path": str(path.absolute()), "copy": name, "sha256": sha(data)})
            seen.add(str(path.absolute()))
    result = subprocess.run([driver, *arguments], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (trace / "stdout").write_bytes(result.stdout)
    (trace / "stderr").write_bytes(result.stderr)
    outputs = []
    candidates = []
    if any(path.endswith((".c", ".o")) for path in arguments):
        if "-c" in arguments:
            candidates = [Path(Path(path).stem + ".o") for path in arguments if path.endswith(".c")]
        elif "-E" not in arguments:
            candidates = [Path("a.out")]
    explicit_output = None
    for index, argument in enumerate(arguments):
        if argument == "-o" and index + 1 < len(arguments):
            explicit_output = Path(arguments[index + 1])
        elif argument.startswith("-o") and len(argument) > 2:
            explicit_output = Path(argument[2:])
    if explicit_output is not None:
        candidates = [explicit_output]
    if result.returncode == 0:
        seen = set()
        for path in candidates:
            if path.is_file() and str(path.absolute()) not in seen:
                data = path.read_bytes()
                name = f"output-{len(outputs)}"
                (trace / name).write_bytes(data)
                (trace / name).chmod(path.stat().st_mode & 0o777)
                outputs.append({"path": str(path.absolute()), "copy": name, "sha256": sha(data)})
                seen.add(str(path.absolute()))
    write_json(trace / "invocation.json", {"arguments": arguments, "cwd": str(Path.cwd()),
               "driver": driver, "inputs": inputs, "returncode": result.returncode,
               "outputs": outputs,
               "stdout_sha256": sha(result.stdout), "stderr_sha256": sha(result.stderr)})
    sys.stdout.buffer.write(result.stdout)
    sys.stderr.buffer.write(result.stderr)
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


def guard(log, name, arguments):
    # One append write keeps concurrent guard events legible.
    event = json.dumps({"tool": name, "arguments": arguments, "cwd": str(Path.cwd())}) + "\n"
    with open(log, "a") as stream:
        stream.write(event)
    print(f"direct-gcc: host target tool blocked: {name}", file=sys.stderr)
    return 127


def verify_source(source, archive):
    pins = (ROOT / "gcc64/SOURCES").read_text().splitlines()
    expected = next(line.split()[1] for line in pins if line.startswith(ARCHIVE + " "))
    if sha(archive.read_bytes()) != expected:
        raise RuntimeError("GCC archive differs from gcc64/SOURCES")
    hashes = {}
    with tarfile.open(archive) as tape:
        for member in tape:
            relative = Path(member.name).relative_to("gcc-4.0.4")
            if ".." in relative.parts:
                raise RuntimeError("unexpected archive pathname")
            path = source / relative
            if member.isfile():
                wanted = sha(tape.extractfile(member).read())
                if not path.is_file() or sha(path.read_bytes()) != wanted:
                    raise RuntimeError(f"original GCC source differs: {relative}")
                hashes[str(relative)] = wanted
            elif member.issym():
                if not path.is_symlink() or os.readlink(path) != member.linkname:
                    raise RuntimeError(f"original GCC symlink differs: {relative}")
                hashes[str(relative)] = {"symlink": member.linkname}
            elif not member.isdir():
                raise RuntimeError(f"unsupported archive member: {relative}")
    actual = {str(path.relative_to(source)) for path in source.rglob("*")
              if (path.is_file() or path.is_symlink()) and path.relative_to(source).parts[0] != ".git"}
    if actual != set(hashes):
        raise RuntimeError("unarchived or missing GCC source paths: " + ", ".join(sorted(actual ^ set(hashes))[:10]))
    return {"archive": str(archive), "archive_sha256": expected, "files": hashes}


def snapshot(work):
    names = ["000-seed.hex0", "seed-forth", "010-lib.fth", "tools/gcc-direct-cc.py",
             "gcc-direct/configure.py"]
    names += [name for name in ("141-archive.fth", "tools/gcc-direct-ar.py") if (ROOT / name).is_file()]
    names += [p.name for p in ROOT.glob("[0-9][0-9][0-9]-cc-*.fth") if p.name != "120-cc-main.fth"]
    names += [str(p.relative_to(ROOT)) for p in (ROOT / "runtime/gcc-seed").rglob("*")
              if p.is_file() and p.suffix in (".c", ".h")]
    data = {name: (ROOT / name).read_bytes() for name in sorted(set(names))}
    if any((ROOT / name).read_bytes() != value for name, value in data.items()):
        raise RuntimeError("compiler inputs changed during snapshot; retry after source freeze")
    toolchain = work / "toolchain"
    hashes = {}
    for name, value in data.items():
        target = toolchain / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(value)
        target.chmod((ROOT / name).stat().st_mode & 0o777)
        hashes[name] = sha(value)
    write_json(work / "toolchain-inputs.json", hashes)
    return toolchain


def summarize(work):
    records = []
    for path in sorted((work / "probes").glob("*/invocation.json")):
        item = json.loads(path.read_text())
        item["trace"] = str(path.parent.relative_to(work))
        item["diagnostic"] = (path.parent / "stderr").read_text(errors="replace")
        records.append(item)
    write_json(work / "probe-inventory.json", records)
    return {"invocations": len(records),
            "successful": sum(item["returncode"] == 0 for item in records),
            "failed": sum(item["returncode"] != 0 for item in records)}


def gencheck(work, source, environment):
    """Original Makefile compilation plus a deliberately narrowed static link."""
    build = work / "build/gcc"
    command = ["make", "CFLAGS=", "LDFLAGS=", "build/gencheck.o"]
    with (work / "gencheck-make.log").open("wb") as log:
        compiled = subprocess.run(command, cwd=build, env=environment, stdout=log, stderr=subprocess.STDOUT)
    report = {"configuration": "provisional; this does not validate all configure answers",
              "compile_command": command, "compile_returncode": compiled.returncode,
              "link_scope": "original gencheck object plus bounded runtime; no BUILD_LIBIBERTY/archive closure"}
    if compiled.returncode:
        write_json(work / "gencheck-report.json", report)
        return report
    executable = build / "build/gencheck-direct"
    driver = work / "toolchain/tools/gcc-direct-cc.py"
    recipe = work / "toolchain/gcc-direct/configure.py"
    command = [sys.executable, str(recipe), "--invoke", str(driver), str(work / "probes"),
               "build/gencheck.o", "-o", str(executable)]
    with (work / "gencheck-link.log").open("wb") as log:
        linked = subprocess.run(command, cwd=build, env=environment, stdout=log, stderr=subprocess.STDOUT)
    report.update({"link_command": command, "link_returncode": linked.returncode})
    if linked.returncode == 0:
        result = subprocess.run([executable], capture_output=True)
        (work / "tree-check.h").write_bytes(result.stdout)
        (work / "gencheck.stderr").write_bytes(result.stderr)
        usage = subprocess.run([executable, "unexpected"], capture_output=True)
        # This is a text-output oracle, not a producer of any target artifact.
        if (build / "gencheck.h").read_bytes().strip():
            raise RuntimeError("C-only gencheck oracle expected an empty configured language-tree include list")
        codes = []
        for name in ("tree.def", "c-common.def"):
            text = (source / "gcc" / name).read_text()
            for match in re.finditer(r"^DEFTREECODE\s*\(\s*([A-Za-z_][A-Za-z_0-9]*)\s*,", text, re.M):
                if match[1] not in codes:
                    codes.append(match[1])
        expected = "/* This file is generated using gencheck. Do not edit. */\n\n"
        expected += "#ifndef GCC_TREE_CHECK_H\n#define GCC_TREE_CHECK_H\n\n"
        expected += "".join(f"#define {name}_CHECK(t)\tTREE_CHECK (t, {name})\n" for name in codes)
        expected += "\n#endif /* GCC_TREE_CHECK_H */\n"
        report.update({"execution_returncode": result.returncode, "output_bytes": len(result.stdout),
                       "output_sha256": sha(result.stdout), "source_tree_code_count": len(codes),
                       "exact_source_derived_output_match": result.stdout == expected.encode(),
                       "execution_stderr": result.stderr.decode(errors="replace"),
                       "usage_returncode": usage.returncode, "usage_stderr": usage.stderr.decode(errors="replace"),
                       "usage_stdout": usage.stdout.decode(errors="replace"),
                       "object_sha256": sha((build / "build/gencheck.o").read_bytes()),
                       "executable_sha256": sha(executable.read_bytes()), "host_target_tools_used": False})
    write_json(work / "gencheck-report.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "build-out/direct-gcc-inputs/gcc-source")
    parser.add_argument("--archive", type=Path, default=ROOT / "build-out/direct-gcc-inputs" / ARCHIVE)
    parser.add_argument("--component", choices=("gcc", "libiberty", "libcpp", "top"), default="gcc")
    parser.add_argument("--work", type=Path, help="new directory; existing directories are rejected")
    parser.add_argument("--gencheck", action="store_true", help="also compile/link/verify original gencheck; configuration remains provisional")
    parser.add_argument("--forth-ar", action="store_true", help="use the frozen Forth archive/index adapter for AR and RANLIB")
    arguments = parser.parse_args()
    if arguments.gencheck and arguments.component != "gcc":
        parser.error("--gencheck requires --component gcc")
    source = arguments.source.resolve()
    source_proof = verify_source(source, arguments.archive.resolve())
    if arguments.work:
        work = arguments.work.absolute()
        work.mkdir(parents=True, exist_ok=False)
    else:
        (ROOT / "build-out").mkdir(exist_ok=True)
        work = Path(tempfile.mkdtemp(prefix="direct-configure-", dir=ROOT / "build-out"))
    write_json(work / "gcc-source-inputs.json", source_proof)
    toolchain = snapshot(work)
    driver = toolchain / "tools/gcc-direct-cc.py"
    recipe = toolchain / "gcc-direct/configure.py"
    archive_driver = toolchain / "tools/gcc-direct-ar.py"
    if arguments.forth_ar and not (archive_driver.is_file() and (toolchain / "141-archive.fth").is_file()):
        raise RuntimeError("--forth-ar requires tools/gcc-direct-ar.py and 141-archive.fth")
    trace = work / "probes"
    trace.mkdir()
    guards = work / "guard"
    guards.mkdir()
    guard_log = work / "host-tool-attempts.jsonl"
    for name in ("gcc", "cc", "clang", "clang++", "g++", "c++", "tcc", "cpp",
                 "as", "ld", "ar", "ranlib", "nm", "strip", "objcopy", "gcj", "gfortran"):
        for spelling in (name, TRIPLE + "-" + name):
            target = guards / spelling
            target.write_text("#!/bin/sh\nexec " + shlex.join([sys.executable, str(recipe), "--guard",
                              str(guard_log), spelling]) + ' "$@"\n')
            target.chmod(0o755)
    cc = shlex.join([sys.executable, str(recipe), "--invoke", str(driver), str(trace)])
    environment = {key: value for key, value in os.environ.items()
                   if not re_cache_variable(key)}
    environment.update({"PATH": str(guards) + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
                        "LC_ALL": "C", "CONFIG_SITE": "/dev/null", "CC": cc, "CPP": cc + " -E",
                        "CXX": str(guards / "c++"), "CXXCPP": str(guards / "cpp"),
                        "CC_FOR_BUILD": cc, "CFLAGS": "", "CPPFLAGS": "", "LDFLAGS": "", "LIBS": "",
                        "CFLAGS_FOR_BUILD": "", "CXXFLAGS": "", "AS": str(guards / "as"),
                        "LD": str(guards / "ld"), "AR": str(guards / "ar"), "RANLIB": str(guards / "ranlib"),
                        "NM": str(guards / "nm"), "AS_FOR_TARGET": str(guards / "as"),
                        "LD_FOR_TARGET": str(guards / "ld")})
    if arguments.forth_ar:
        environment["AR"] = shlex.join([sys.executable, str(archive_driver)])
        environment["RANLIB"] = environment["AR"] + " s"
    build = work / "build" / ("top" if arguments.component == "top" else arguments.component)
    build.mkdir(parents=True)
    configure = source / ("" if arguments.component == "top" else arguments.component) / "configure"
    command = ["/bin/sh", str(configure), "--build=" + TRIPLE, "--host=" + TRIPLE,
               "--target=" + TRIPLE, "--prefix=" + str(work / "install"),
               "--disable-shared", "--disable-nls", "--disable-multilib", "--enable-languages=c",
               "--cache-file=/dev/null", "--with-as=" + str(guards / "as"),
               "--with-ld=" + str(guards / "ld"), "--program-transform-name="]
    write_json(work / "configure-command.json", {"command": command, "cwd": str(build),
               "environment": {key: environment[key] for key in ("CC", "CPP", "CXX", "CXXCPP", "CC_FOR_BUILD",
                 "CFLAGS", "CPPFLAGS", "LDFLAGS", "LIBS", "CONFIG_SITE", "PATH", "AS", "LD", "AR", "RANLIB", "NM")}})
    print(work, flush=True)
    with (work / "configure.log").open("wb") as log:
        result = subprocess.run(command, cwd=build, env=environment, stdout=log, stderr=subprocess.STDOUT)
    report = {"configuration": "provisional; probe and generated-header audit required",
              "component": arguments.component, "returncode": result.returncode,
              "gcc_source_sha256": source_proof["archive_sha256"], "work": str(work),
              "compiler": "frozen Forth source snapshot", "host_target_tools": "guarded; attempts retained",
              "archive_adapter": "Forth fresh indexed archives" if arguments.forth_ar else "guarded, unavailable",
              "probes": summarize(work)}
    write_json(work / "report.json", report)
    print(json.dumps(report, indent=2), flush=True)
    if result.returncode == 0 and arguments.gencheck:
        generator = gencheck(work, source, environment)
        print(json.dumps(generator, indent=2), flush=True)
        if not (generator.get("execution_returncode") == 0
                and generator.get("exact_source_derived_output_match")
                and not generator.get("execution_stderr")
                and generator.get("usage_returncode") == 1
                and generator.get("usage_stderr") == "Usage: gencheck\n"
                and not generator.get("usage_stdout")):
            return 1
    return result.returncode


def re_cache_variable(name):
    return "_cv_" in name or name.startswith(("ac_cv", "gcc_cv", "gt_cv"))


if __name__ == "__main__":
    try:
        if sys.argv[1:2] == ["--invoke"]:
            sys.exit(invoke(sys.argv[2], sys.argv[3], sys.argv[4:]))
        if sys.argv[1:2] == ["--guard"]:
            sys.exit(guard(sys.argv[2], sys.argv[3], sys.argv[4:]))
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, StopIteration) as error:
        print(f"direct-configure: {error}", file=sys.stderr)
        sys.exit(1)
