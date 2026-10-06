#!/usr/bin/env python3
"""Run unmodified pinned GCC or binutils configure with a frozen Forth toolchain.

Configuration is provisional: the retained probe sources and outcomes must be
audited before feature answers are treated as compiler/runtime evidence.

Host target tools (as, ld, nm, ...) are guarded by default: GCC is configured
with --with-as/--with-ld naming the guards, so no host binutils answers a probe.
Those paths are also baked into the driver as DEFAULT_ASSEMBLER/DEFAULT_LINKER,
which gcc.c and collect2.c prefer over any -B directory.  --with-binutils DIR
instead names a directory of Forth-built binutils (as and ld required; nm,
objdump, ar, ranlib optional): --with-as=DIR/as, --with-ld=DIR/ld,
*_FOR_TARGET for each present tool and, for the gcc component, ./nm and
./objdump links in the build directory (how GCC 4.0.4's configure and Makefile
find target nm/objdump).  --with-sysroot DIR passes GCC's own --with-sysroot,
so the driver and cc1 search DIR/usr/include and DIR/usr/lib, never the host's
/usr.  Every host-side tool stays guarded.
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
# Pinned source archives (hashes in gcc64/SOURCES) and their top directories.
PACKAGES = {
    "gcc": {"archive": "gcc-4.0.4-git-944765863e.tar", "top": "gcc-4.0.4",
            "inputs": "build-out/direct-gcc-inputs", "source": "gcc-source"},
    "binutils": {"archive": "binutils-2.30.tar.xz", "top": "binutils-2.30",
                 "inputs": "build-out/stage-b-inputs", "source": "binutils-source",
            # Only the assembler, linker and archive tools are in scope.
            "options": ["--disable-gold", "--disable-gprof", "--disable-plugins", "--disable-werror"],
            # No C++ compiler exists on this route.  ld's configure runs AC_PROG_CXX and
            # libtool then sanity-checks a C++ preprocessor unless CXX is exactly "no".
            "environment": {"CXX": "no"},
            # Parser/scanner C shipped in the release tarball.  The source view omits
            # them so make must regenerate each from its .y/.l with the Forth-built
            # oyacc and flex; hand-written ldlex.h, itbl-lex.h, m68k-parse.h remain.
            "generated": [
                "binutils/arlex.c", "binutils/arparse.c", "binutils/arparse.h",
                "binutils/deflex.c", "binutils/defparse.c", "binutils/defparse.h",
                "binutils/mcparse.c", "binutils/mcparse.h", "binutils/nlmheader.c",
                "binutils/nlmheader.h", "binutils/rcparse.c", "binutils/rcparse.h",
                "binutils/sysinfo.c", "binutils/sysinfo.h", "binutils/syslex.c",
                "gas/itbl-lex.c", "gas/itbl-parse.c", "gas/itbl-parse.h",
                "intl/plural.c", "ld/deffilep.c", "ld/deffilep.h",
                "ld/ldgram.c", "ld/ldgram.h", "ld/ldlex.c"]},
}
ARCHIVE = PACKAGES["gcc"]["archive"]
TRIPLE = "x86_64-pc-linux-gnu"
# --with-binutils: tools the directory may supply, mapped to GCC's variables.
TARGET_TOOLS = {"as": "AS_FOR_TARGET", "ld": "LD_FOR_TARGET", "nm": "NM_FOR_TARGET",
                "objdump": "OBJDUMP_FOR_TARGET", "ar": "AR_FOR_TARGET",
                "ranlib": "RANLIB_FOR_TARGET"}


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


def verify_source(source, archive, package="gcc"):
    pins = (ROOT / "gcc64/SOURCES").read_text().splitlines()
    name = PACKAGES[package]["archive"]
    expected = next(line.split()[1] for line in pins if line.startswith(name + " "))
    if sha(archive.read_bytes()) != expected:
        raise RuntimeError(f"{package} archive differs from gcc64/SOURCES")
    hashes = {}
    with tarfile.open(archive) as tape:
        for member in tape:
            relative = Path(member.name).relative_to(PACKAGES[package]["top"])
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
    names += [name for name in ("141-archive.fth", "tools/gcc-direct-ar.py", "gcc-direct/replay.py") if (ROOT / name).is_file()]
    names += [str(path.relative_to(ROOT)) for path in (ROOT / "gcc-direct/patches").glob("alloca-frame.*")]
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


def prepare_generated_free_source(source, work, omitted):
    """Symlink view of SOURCE without the shipped generated files in OMITTED."""
    view = work / "source-view"

    def mirror(directory, target, prefix):
        target.mkdir()
        for entry in sorted(directory.iterdir()):
            relative = prefix + entry.name
            if relative in omitted:
                continue
            if entry.is_dir() and not entry.is_symlink() and any(o.startswith(relative + "/") for o in omitted):
                mirror(entry, target / entry.name, relative + "/")
            else:
                (target / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())

    missing = [name for name in omitted if not (source / name).is_file()]
    if missing:
        raise RuntimeError("listed generated files are absent: " + ", ".join(missing))
    mirror(source, view, "")
    write_json(work / "source-view.json", {"original_source": str(source), "prepared_source": str(view),
               "omitted_generated_files": {name: sha((source / name).read_bytes()) for name in sorted(omitted)},
               "scope": "Shipped generated parsers/scanners removed; make regenerates them from .y/.l"})
    return view


def prepare_alloca_source(source, work):
    """Make an explicit source view with one hash-checked target adapter."""
    directory = ROOT / "gcc-direct/patches"
    patch = directory / "alloca-frame.patch"
    manifest = json.loads((directory / "alloca-frame.json").read_text())
    original = source / manifest["source"]
    if sha(original.read_bytes()) != manifest["before_sha256"] or sha(patch.read_bytes()) != manifest["patch_sha256"]:
        raise RuntimeError("alloca target adapter source or patch hash differs")
    view = work / "gcc-source"
    view.mkdir()
    for entry in source.iterdir():
        if entry.name == ".git":
            continue
        if entry.name != "libiberty":
            (view / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
            continue
        (view / "libiberty").mkdir()
        for member in entry.iterdir():
            destination = view / "libiberty" / member.name
            if member.name == "alloca.c":
                destination.write_bytes(member.read_bytes())
            else:
                destination.symlink_to(member, target_is_directory=member.is_dir())
    result = subprocess.run(["patch", "--batch", "--forward", "--fuzz=0", "-p1", "-i", str(patch)],
                            cwd=view, capture_output=True)
    (work / "alloca-adapter.log").write_bytes(result.stdout + result.stderr)
    if result.returncode or sha((view / manifest["source"]).read_bytes()) != manifest["after_sha256"]:
        raise RuntimeError("exact alloca target adapter application failed")
    save = {**manifest, "original_source": str(source), "prepared_source": str(view),
            "scope": "One explicit target-guarded source patch; no configuration answer changes"}
    write_json(work / "alloca-adapter.json", save)
    return view


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
    parser.add_argument("--package", choices=sorted(PACKAGES), default="gcc")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--component", choices=("gcc", "libiberty", "libcpp", "top"), default="gcc",
                        help="GCC subdirectory to configure; binutils always configures its top level")
    parser.add_argument("--work", type=Path, help="new directory; existing directories are rejected")
    parser.add_argument("--gencheck", action="store_true", help="also compile/link/verify original gencheck; configuration remains provisional")
    parser.add_argument("--forth-ar", action="store_true", help="use the frozen Forth archive/index adapter for AR and RANLIB")
    parser.add_argument("--alloca-frame", action="store_true", help="apply the exact target-guarded C_alloca stable-frame adapter in a private source view")
    parser.add_argument("--with-binutils", type=Path, metavar="DIR",
                        help="GCC only: use DIR/as and DIR/ld (Forth-built binutils) as the target assembler/linker instead of the guards")
    parser.add_argument("--with-sysroot", type=Path, metavar="DIR",
                        help="GCC only: configure the target system root (target headers in DIR/usr/include)")
    arguments = parser.parse_args()
    if arguments.gencheck and arguments.component != "gcc":
        parser.error("--gencheck requires --component gcc")
    package = PACKAGES[arguments.package]
    if arguments.package != "gcc":
        if arguments.gencheck or arguments.alloca_frame or arguments.with_binutils or arguments.with_sysroot:
            parser.error("--gencheck, --alloca-frame, --with-binutils and --with-sysroot apply to GCC only")
        arguments.component = "top"
    target_tools = {}
    if arguments.with_binutils:
        binutils = arguments.with_binutils.resolve()
        for name in TARGET_TOOLS:
            path = binutils / name
            if path.is_file() and os.access(path, os.X_OK):
                target_tools[name] = path
            elif name in ("as", "ld"):
                parser.error(f"--with-binutils needs an executable {path}")
    sysroot = arguments.with_sysroot.resolve() if arguments.with_sysroot else None
    if sysroot and not (sysroot / "usr/include").is_dir():
        parser.error(f"--with-sysroot needs target headers in {sysroot / 'usr/include'}")
    source = (arguments.source or ROOT / package["inputs"] / package["source"]).resolve()
    archive = (arguments.archive or ROOT / package["inputs"] / package["archive"]).resolve()
    source_proof = verify_source(source, archive, arguments.package)
    if arguments.work:
        work = arguments.work.absolute()
        work.mkdir(parents=True, exist_ok=False)
    else:
        (ROOT / "build-out").mkdir(exist_ok=True)
        work = Path(tempfile.mkdtemp(prefix="direct-configure-", dir=ROOT / "build-out"))
    write_json(work / "gcc-source-inputs.json", source_proof)
    if package.get("generated"):
        source = prepare_generated_free_source(source, work, set(package["generated"]))
    if arguments.alloca_frame:
        source = prepare_alloca_source(source, work)
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
    environment.update(package.get("environment", {}))
    if arguments.forth_ar:
        environment["AR"] = shlex.join([sys.executable, str(archive_driver)])
        environment["RANLIB"] = environment["AR"] + " s"
    environment.update({TARGET_TOOLS[name]: str(path) for name, path in target_tools.items()})
    target_as = target_tools.get("as", guards / "as")
    target_ld = target_tools.get("ld", guards / "ld")
    build = work / "build" / ("top" if arguments.component == "top" else arguments.component)
    build.mkdir(parents=True)
    if arguments.component == "gcc":
        # gcc/configure takes `test -x nm` / `test -x objdump` in its build
        # directory first; the Makefile's NM_FOR_TARGET likewise prefers ./nm.
        for name in ("nm", "objdump"):
            if name in target_tools:
                (build / name).symlink_to(target_tools[name])
    configure = source / ("" if arguments.component == "top" else arguments.component) / "configure"
    command = ["/bin/sh", str(configure), "--build=" + TRIPLE, "--host=" + TRIPLE,
               "--target=" + TRIPLE, "--prefix=" + str(work / "install"),
               "--disable-shared", "--disable-nls", "--disable-multilib", "--enable-languages=c",
               "--cache-file=/dev/null", "--with-as=" + str(target_as),
               "--with-ld=" + str(target_ld), "--program-transform-name="]
    command += package.get("options", [])
    if sysroot:
        command.append("--with-sysroot=" + str(sysroot))
    write_json(work / "configure-command.json", {"command": command, "cwd": str(build),
               "environment": {key: environment[key] for key in ("CC", "CPP", "CXX", "CXXCPP", "CC_FOR_BUILD",
                 "CFLAGS", "CPPFLAGS", "LDFLAGS", "LIBS", "CONFIG_SITE", "PATH", "AS", "LD", "AR", "RANLIB", "NM")},
               "target_tools": {name: str(path) for name, path in target_tools.items()}})
    print(work, flush=True)
    with (work / "configure.log").open("wb") as log:
        result = subprocess.run(command, cwd=build, env=environment, stdout=log, stderr=subprocess.STDOUT)
    report = {"configuration": "provisional; probe and generated-header audit required",
              "component": arguments.component, "returncode": result.returncode,
              "gcc_source_sha256": source_proof["archive_sha256"], "work": str(work),
              "compiler": "frozen Forth source snapshot", "host_target_tools": "guarded; attempts retained",
              "target_binutils": {name: {"path": str(path), "sha256": sha(path.read_bytes())}
                                  for name, path in target_tools.items()} or "guarded, unavailable",
              "sysroot": str(sysroot) if sysroot else None,
              "archive_adapter": "Forth fresh indexed archives" if arguments.forth_ar else "guarded, unavailable",
              "alloca_adapter": "explicit Forth caller-frame depth" if arguments.alloca_frame else "unmodified original C_alloca",
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
