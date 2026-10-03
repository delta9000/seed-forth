#!/usr/bin/env python3
"""Independent bounded genmodes source-closure and entire-output audit.

Retained configure inputs are read-only. Replays and host-oracle artifacts stay
in a fresh review directory. Host code is never a Forth production input.
"""
from pathlib import Path
from collections import Counter
import argparse
import difflib
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_SHA = "091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67"
TARGET_SHA = "0141dec67f7141c1f2bb4096ad18fb2a7628f4a7ea5258acd9dc736491c6330d"
MEMBERS = ("alloca", "hashtab", "xmalloc", "xstrdup", "xexit")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha(path):
    return digest(path.read_bytes())


def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def verify(path, expected):
    assert sha(path) == expected, str(path)


def symbols(path):
    """Independently decode ELF symbols, without invoking host target tools."""
    data = path.read_bytes()
    assert data[:6] == b"\x7fELF\x02\x01", path
    head = struct.unpack_from("<16sHHIQQQIHHHHHH", data)
    assert head[2] == 62, path
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, head[6] + i * head[11])
                for i in range(head[12])]
    result = {"defined": [], "undefined": []}
    for section in sections:
        if section[1] != 2:
            continue
        table = sections[section[6]]
        strings = data[table[4]:table[4] + table[5]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            name, info, _, index, _, _ = struct.unpack_from("<IBBHQQ", data, offset)
            if name and info >> 4 in (1, 2):
                name = strings[name:strings.index(b"\0", name)].decode()
                result["defined" if index else "undefined"].append(name)
    return {key: sorted(set(value)) for key, value in result.items()}


def archive_members(path):
    data = path.read_bytes()
    assert data[:8] == b"!<arch>\n"
    offset, result = 8, []
    while offset < len(data):
        header = data[offset:offset + 60]
        assert len(header) == 60 and header[-2:] == b"`\n"
        name, size = header[:16].decode().strip(), int(header[48:58])
        body = data[offset + 60:offset + 60 + size]
        assert len(body) == size
        result.append({"name": name, "sha256": digest(body), "offset": offset, "size": size})
        offset += 60 + size + size % 2
    assert offset == len(data)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gcc_work", type=Path)
    parser.add_argument("libiberty_work", type=Path)
    args = parser.parse_args()
    work, library = args.gcc_work.resolve(), args.libiberty_work.resolve()
    out = Path(tempfile.mkdtemp(prefix="review-genmodes-", dir=ROOT / "build-out"))
    print(out, flush=True)
    shutil.copy2(Path(__file__), out / "review-script.py")
    script_sha = sha(out / "review-script.py")
    calls = []

    def run(name, argv, cwd=out, env=None):
        argv = list(map(str, argv))
        result = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, timeout=120)
        (out / (name + ".stdout")).write_bytes(result.stdout)
        (out / (name + ".stderr")).write_bytes(result.stderr)
        calls.append({"name": name, "argv": argv, "cwd": str(cwd),
                      "returncode": result.returncode, "stdout_sha256": digest(result.stdout),
                      "stderr_sha256": digest(result.stderr)})
        save(out / "commands.json", calls)
        assert result.returncode == 0, (name, result.returncode, result.stderr.decode(errors="replace"))
        return result

    production = load(work / "genmodes-report.json")
    assert production["archive_members"] == list(MEMBERS)
    assert production["full_libiberty_build"] is False
    manifests = [load(root / "toolchain-inputs.json") for root in (work, library)]
    assert manifests[0] == manifests[1], "different compiler compositions"
    for root, manifest in zip((work, library), manifests):
        assert load(root / "report.json")["returncode"] == 0
        for name, expected in manifest.items():
            verify(root / "toolchain" / name, expected)
    manifest = manifests[0]
    # A fresh source-only copy forces independent runtime generation rather
    # than trusting provenance labels on previously cached object bytes.
    toolchain = out / "toolchain"
    for name in manifest:
        target = toolchain / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(work / "toolchain" / name, target)
    cc = toolchain / "tools/gcc-direct-cc.py"
    source_manifest = load(work / "gcc-source-inputs.json")
    assert source_manifest == load(library / "gcc-source-inputs.json")
    archive = Path(source_manifest["archive"])
    verify(archive, ARCHIVE_SHA)
    source = Path(load(work / "configure-command.json")["command"][1]).parent.parent
    verified = {}
    with tarfile.open(archive) as tape:
        for member in tape:
            relative = Path(member.name).relative_to("gcc-4.0.4")
            assert ".." not in relative.parts
            path = source / relative
            if member.isfile():
                expected = digest(tape.extractfile(member).read())
                verify(path, expected)
                verified[str(relative)] = expected
            elif member.issym():
                assert path.is_symlink() and os.readlink(path) == member.linkname
                verified[str(relative)] = {"symlink": member.linkname}
            else:
                assert member.isdir()
    assert verified == source_manifest["files"]
    actual = {str(p.relative_to(source)) for p in source.rglob("*")
              if (p.is_file() or p.is_symlink()) and p.relative_to(source).parts[0] != ".git"}
    assert actual == set(verified), "extra/missing original source paths"
    adapter = load(library / "alloca-adapter.json")
    adapted = Path(adapter["prepared_source"])
    patch = work / "toolchain/gcc-direct/patches/alloca-frame.patch"
    verify(patch, adapter["patch_sha256"])
    verify(source / "libiberty/alloca.c", adapter["before_sha256"])
    verify(adapted / "libiberty/alloca.c", adapter["after_sha256"])
    patch_view = out / "patch-replay/libiberty"
    patch_view.mkdir(parents=True)
    shutil.copyfile(source / "libiberty/alloca.c", patch_view / "alloca.c")
    run("exact-patch", ["patch", "--batch", "--fuzz=0", "-p1", "-i", patch], patch_view.parent)
    verify(patch_view / "alloca.c", adapter["after_sha256"])
    for name, expected in verified.items():
        if name == "libiberty/alloca.c":
            continue
        path = adapted / name
        if isinstance(expected, str):
            verify(path, expected)
        else:
            assert path.is_symlink() and os.readlink(path) == expected["symlink"]

    build, libbuild = work / "build/gcc", library / "build/libiberty"
    rules = {}
    for component, generated, prefixes in (
            ("gcc", build, ("$(genobjs):", "build/genmodes$(build_exeext)", "build/genmodes.o :")),
            ("libiberty", libbuild, ("$(TARGETLIB):", *["./" + n + ".o:" for n in MEMBERS]))):
        original = (source / component / "Makefile.in").read_text()
        actual_makefile = (generated / "Makefile").read_text()
        for prefix in prefixes:
            blocks = [block for block in original.split("\n\n") if block.startswith(prefix)]
            assert len(blocks) == 1 and blocks[0] in actual_makefile, (component, prefix)
            rules[component + "/" + prefix] = blocks[0]
    library_makefile = (libbuild / "Makefile").read_text().replace("\\\n", " ")
    default_library_inputs = {key: re.search(r"^" + key + r"\s*=(.*)$", library_makefile, re.M).group(1).split()
                              for key in ("REQUIRED_OFILES", "EXTRA_OFILES", "LIBOBJS")}
    assert sum(map(len, default_library_inputs.values())) == 75
    header_pins = {str(p): sha(p) for root in (build, libbuild) for p in root.rglob("*.h") if p.is_file()}
    for root, key in ((build, "generated_gcc_headers"), (libbuild, "generated_libiberty_headers")):
        for name, expected in load(work / "genmodes-inputs.json")[key].items():
            verify(root / name, expected)
    traces = {}
    for component, root in (("gcc", work), ("libiberty", library)):
        traces[component] = []
        for path in sorted((root / "probes").glob("*/invocation.json")):
            trace = load(path)
            for entry in trace["inputs"] + trace["outputs"]:
                verify(path.parent / entry["copy"], entry["sha256"])
            for stream in ("stdout", "stderr"):
                verify(path.parent / stream, trace[stream + "_sha256"])
            trace["trace"] = str(path)
            trace["body"] = "\n".join((path.parent / e["copy"]).read_text()
                                      for e in trace["inputs"] if e["copy"].endswith(".c"))
            traces[component].append(trace)
    object_report = {}
    for component, names in (("gcc", ("genmodes", "errors")), ("libiberty", MEMBERS)):
        for name in names:
            selected = [t for t in traces[component] if not t["returncode"] and "-c" in t["arguments"]
                        and any(a.endswith("/" + name + ".c") for a in t["arguments"])]
            assert selected, (component, name)
            trace = selected[-1]
            argv = list(trace["arguments"])
            if component == "gcc":
                assert all(flag in argv for flag in ("-DIN_GCC", "-DHAVE_CONFIG_H", "-DGENERATOR_FILE"))
            obj = out / (name + ".o")
            argv[argv.index("-o") + 1] = str(obj)
            run("forth-" + name, [cc, *argv], Path(trace["cwd"]))
            expected = production["generator_objects" if component == "gcc" else "archive_objects"][name]
            verify(obj, expected)
            object_report[name] = {"sha256": sha(obj), "trace": trace["trace"],
                                   "arguments": trace["arguments"], **symbols(obj)}
            if name == "genmodes":
                pp_args = list(argv)
                del pp_args[pp_args.index("-o"):pp_args.index("-o") + 2]
                pp_args[pp_args.index("-c")] = "-E"
                pp = run("preprocess", [cc, *pp_args], Path(trace["cwd"])).stdout
                assert digest(pp) == production["preprocessed_sha256"]
                pp_text = pp.decode()
                verify(source / "gcc/config/i386/i386-modes.def", TARGET_SHA)
                for marker in production["target_definition"]["markers_consumed"]:
                    assert re.search(r"\b" + marker + r"\b", pp_text), marker
                assert 'machmode.def' in pp_text and 'i386-modes.def' in pp_text
    reviewed_archive = out / "libiberty.a"
    ar = toolchain / "tools/gcc-direct-ar.py"
    run("forth-archive", [ar, "rc", reviewed_archive, *[out / (n + ".o") for n in MEMBERS]])
    run("forth-index", [ar, "s", reviewed_archive])
    verify(reviewed_archive, production["archive_sha256"])
    members = archive_members(reviewed_archive)
    assert members[0]["name"] == "/"
    assert [m["name"] for m in members[1:]] == [n + ".o/" for n in MEMBERS]
    for member, name in zip(members[1:], MEMBERS):
        assert member["sha256"] == object_report[name]["sha256"]
    executable = out / "genmodes"
    link = [t for t in traces["gcc"] if "build/genmodes.o" in t["arguments"] and "-c" not in t["arguments"]][-1]
    argv = [str(executable) if a == "build/genmodes" else
            str(out / Path(a).name) if a.endswith((".o", ".a")) else a for a in link["arguments"]]
    run("forth-link", [cc, *argv], Path(link["cwd"]))
    verify(executable, production["executable_sha256"])
    identity = run("identity", [cc, "--print-source-hash"]).stdout.decode().strip()
    cache = toolchain / "build-out/gcc-direct-cache" / identity
    runtime = load(cache / "manifest.json")
    expected_runtime_sources = {k: v for k, v in manifest.items()
                                if not k.startswith("gcc-direct/") and k != "tools/gcc-direct-ar.py"}
    assert runtime["source_sha256"] == expected_runtime_sources
    assert runtime["host_compiler"] is False and runtime["host_linker"] is False
    runtime_symbols = {}
    for name, expected in runtime["artifact_sha256"].items():
        verify(cache / name, expected)
        runtime_symbols[name] = {"sha256": expected, **symbols(cache / name)}
    all_objects = {**object_report, **runtime_symbols}
    providers = {}
    for name, item in all_objects.items():
        for symbol in item["defined"]:
            providers.setdefault(symbol, []).append(name)
    missing = sorted({s for item in all_objects.values() for s in item["undefined"] if s not in providers})
    assert not missing, missing
    assert providers["qsort"] == ["sort.o"] and providers["__seed_parent_frame"] == ["frame.o"]
    assert "C_alloca" in object_report["alloca"]["defined"]
    assert "__seed_parent_frame" in object_report["alloca"]["undefined"]
    eager = [runtime_symbols["start.o"], object_report["genmodes"], object_report["errors"]]
    defined = {s for item in eager for s in item["defined"]}
    required = {s for item in eager for s in item["undefined"]}
    selected = []
    while True:
        previous = len(selected)
        for name in MEMBERS:
            obj = object_report[name]
            if name not in selected and (required - defined) & set(obj["defined"]):
                selected.append(name)
                defined.update(obj["defined"])
                required.update(obj["undefined"])
        if previous == len(selected):
            break
    assert selected == list(MEMBERS), selected

    # Real allocator and a separate poison/free-count observer use the same
    # original object bytes as the generator's selected library members.
    fixture = out / "driver-alloca-lifetime.c"
    observer = out / "driver-alloca-observer.c"
    for path in (fixture, observer):
        shutil.copy2(ROOT / "tests/gcc" / path.name, path)
    run("alloca-real-compile", [cc, fixture, out / "alloca.o", out / "xmalloc.o", out / "xexit.o", "-o", out / "alloca-real"])
    real_result = run("alloca-real-run", [out / "alloca-real"])
    run("alloca-observer-compile", [cc, "-nostdlib", "-DOBSERVE_FREES", fixture, observer, out / "alloca.o",
        *[cache / n for n in ("start.o", "syscall.o", "frame.o")], "-o", out / "alloca-observed"])
    observed_result = run("alloca-observer-run", [out / "alloca-observed"])
    assert not real_result.stdout and not real_result.stderr and not observed_result.stdout and not observed_result.stderr

    # Audit the actual original native probes, not substituted success answers.
    macros = dict(re.findall(r"^#define (\w+)(?:[ \t]+([^\n]*))?$", (build / "auto-host.h").read_text(), re.M))
    assert macros["BYTEORDER"] == "1234"
    assert not any(k in macros for k in ("WORDS_BIGENDIAN", "HOST_WORDS_BIG_ENDIAN", "MKDIR_TAKES_ONE_ARG"))
    assert macros["EXTRA_MODES_FILE"] == '"config/i386/i386-modes.def"'
    ansi = re.findall(r"^ac_cv_prog_cc_stdc=(.*)$", (build / "config.log").read_text(), re.M)
    assert ansi in ([""], ["''"])
    probe_report = {}
    for name, needle in {"endian": "From Harbison&Steele", "mkdir": 'mkdir ("foo", 0)',
            "ansi": "int pairnames (int, char **, FILE *(*)(struct buf *, struct stat *, int), int, int);"}.items():
        found = [t for t in traces["gcc"] if needle in t["body"]]
        assert len(found) == 1 and found[0]["returncode"] == 0, name
        t = found[0]
        probe_report[name] = {k: t[k] for k in ("trace", "returncode", "arguments", "inputs", "outputs")}
        if name == "endian":
            result = run("original-endian", [Path(t["trace"]).parent / t["outputs"][0]["copy"]])
            assert not result.stdout and not result.stderr
    sizes = {}
    for t in traces["gcc"]:
        match = re.search(r"long longval \(\) \{ return \(long\) \(sizeof \(([^)]+)\)\); \}", t["body"])
        if match and not t["returncode"]:
            directory = out / ("size-" + match[1].replace(" ", "_").replace("*", "pointer"))
            directory.mkdir()
            run(directory.name, [Path(t["trace"]).parent / t["outputs"][0]["copy"]], directory)
            sizes[match[1]] = (directory / "conftest.val").read_text().strip()
    assert sizes == {"void *": "8", "short": "2", "int": "4", "long": "8", "long long": "8"}, sizes
    fallbacks = {}
    declarations = {
        "MALLOC": ("stdlib.h", "void *malloc(size_t size);", "extern void *malloc (size_t);"),
        "REALLOC": ("stdlib.h", "void *realloc(void *pointer, size_t size);", "extern void *realloc (void *, size_t);"),
        "CALLOC": ("stdlib.h", "void *calloc(size_t count, size_t size);", "extern void *calloc (size_t, size_t);"),
        "FREE": ("stdlib.h", "void free(void *pointer);", "extern void free (void *);"),
        "STRSTR": ("string.h", "char *strstr(const char *haystack, const char *needle);", "extern char *strstr (const char *, const char *);"),
        "SNPRINTF": ("stdio.h", "int snprintf(char *buffer, size_t size, const char *format, ...);", "extern int snprintf (char *, size_t, const char *, ...);")}
    system_h = (source / "gcc/system.h").read_text()
    for name, (header, provided, fallback) in declarations.items():
        found = [t for t in traces["gcc"] if "#undef HAVE_DECL_" + name + "\n" in t["body"]]
        assert len(found) == 1 and found[0]["returncode"] == 143 and macros["HAVE_DECL_" + name] == "0"
        assert provided in (toolchain / "runtime/gcc-seed/include" / header).read_text()
        assert fallback in system_h
        fallbacks[name] = {"configured": 0, "probe_status": 143, "trace": found[0]["trace"],
                           "provided_declaration": provided, "fallback_declaration": fallback,
                           "equivalence": "same return and parameter types; parameter names and whitespace differ"}

    # Separate oracle uses unchanged upstream C_alloca, host libc, and the
    # audited generated branch facts; none of these bytes enters production.
    host = shutil.which("gcc")
    assert host, "host GCC missing; whole-output oracle cannot run"
    host_version = run("oracle-version", [host, "--version"]).stdout.decode().splitlines()[0]
    oracle = out / "host-oracle"
    oracle.mkdir()
    for name in MEMBERS:
        run("oracle-" + name, [host, "-std=c90", "-O0", "-DHAVE_CONFIG_H", "-I" + str(libbuild),
            "-I" + str(source / "include"), "-c", source / "libiberty" / (name + ".c"), "-o", oracle / (name + ".o")])
    run("oracle-genmodes", [host, "-std=c90", "-O0", "-DIN_GCC", "-DHAVE_CONFIG_H", "-DGENERATOR_FILE",
        "-I" + str(build), "-I" + str(source / "gcc"), "-I" + str(source / "include"),
        "-I" + str(source / "libcpp/include"), source / "gcc/genmodes.c", source / "gcc/errors.c",
        *[oracle / (n + ".o") for n in MEMBERS], "-o", oracle / "genmodes"])
    outputs = {}
    for filename, flags in (("insn-modes.h", ["-h"]), ("min-insn-modes.c", ["-m"]), ("insn-modes.c", [])):
        forth = run("forth-output-" + filename, [executable, *flags])
        reference = run("host-output-" + filename, [oracle / "genmodes", *flags])
        assert not forth.stderr and not reference.stderr
        assert digest(forth.stdout) == production["output"][filename]["sha256"]
        assert forth.stdout == (work / filename).read_bytes()
        diff = "".join(difflib.unified_diff(reference.stdout.decode().splitlines(True), forth.stdout.decode().splitlines(True),
                                         fromfile="host", tofile="forth"))
        (out / (filename + ".diff")).write_text(diff)
        outputs[filename] = {"forth_bytes": len(forth.stdout), "forth_sha256": digest(forth.stdout),
                             "host_bytes": len(reference.stdout), "host_sha256": digest(reference.stdout),
                             "whole_output_equal": forth.stdout == reference.stdout}
    for path, expected in header_pins.items():
        verify(Path(path), expected)
    for name, expected in manifest.items():
        verify(work / "toolchain" / name, expected)
        verify(library / "toolchain" / name, expected)
        verify(toolchain / name, expected)
    verify(Path(__file__), script_sha)
    accepted = all(item["whole_output_equal"] for item in outputs.values())
    report = {"status": "PASS" if accepted else "FAIL: entire-output oracle differs",
        "scope": "Source-closed original genmodes/errors, selected five-member original-library archive, bounded seed runtime, explicit target C_alloca adapter",
        "not_claimed": ["Full libiberty library", "complete GCC configuration", "full GCC compiler", "GCC fixed point", "general ISO C conformance"],
        "gcc_work": str(work), "libiberty_work": str(library), "gcc_archive_sha256": ARCHIVE_SHA,
        "original_source_entries_verified": len(verified), "target_modes_sha256": TARGET_SHA,
        "machmode_sha256": sha(source / "gcc/machmode.def"), "compiler_source_sha256": manifest,
        "compiler_identity": identity, "production_report_sha256": sha(work / "genmodes-report.json"),
        "script_sha256": script_sha, "generated_header_sha256": header_pins,
        "original_makefile_rules": rules,
        "default_library_inputs_not_built": default_library_inputs,
        "make_overrides": {"archive": production["archive_command"], "generator": production["generator_command"]},
        "adapter": adapter, "object_replay": object_report, "archive_members": members,
        "archive_sha256": sha(reviewed_archive), "executable_sha256": sha(executable),
        "independently_required_archive_members_in_scan_order": selected,
        "runtime_source_sha256": runtime["source_sha256"], "runtime_objects": runtime_symbols,
        "runtime_replay": "Fresh source-only toolchain copy, initially empty runtime cache; all runtime objects compiled/generated again through Forth",
        "symbol_providers": providers, "unresolved_symbols": missing,
        "alloca_lifetime": {"actual_allocator": "PASS", "separate_observer": "PASS: 13 allocations and 13 frees; poison and duplicate/unknown-free checks",
            "fixture_sha256": sha(fixture), "observer_sha256": sha(observer),
            "real_executable_sha256": sha(out / "alloca-real"), "observer_executable_sha256": sha(out / "alloca-observed")},
        "audited_original_probes": probe_report, "original_size_executions": sizes,
        "declaration_fallbacks": fallbacks, "configuration_scope": "native endian, ANSI, mkdir, LP64 sizes and conservative declaration fallbacks only; missing runtime interfaces remain bounded",
        "configure_probe_counts": {name: dict(Counter(t["returncode"] for t in load(root / "probe-inventory.json"))) for name, root in (("gcc", work), ("libiberty", library))},
        "host_compiler_version": host_version,
        "output": outputs, "host_oracle_isolation": "Fresh host-only directory; unchanged original sources and native C_alloca; outputs never enter Forth compilation or link"}
    save(out / "report.json", report)
    print(report["status"], flush=True)
    print(out / "report.json", flush=True)
    return 0 if accepted else 1


if __name__ == "__main__":
    raise SystemExit(main())
