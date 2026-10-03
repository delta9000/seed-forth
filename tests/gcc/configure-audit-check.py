#!/usr/bin/env python3
"""Audit retained GCC configure evidence without changing its answers.

The output is a report, not a declaration that configure is safe to consume.
No host compiler, assembler, linker, or libc generates the tested code.
"""
from pathlib import Path
import argparse
from collections import Counter
import hashlib
import json
import os
import re
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_SHA = "091f7e50fb712289632fb14d93582a6a49d731c59b8c095cc75cff01c1f40a67"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(path, expected):
    actual = sha(path)
    if actual != expected:
        raise RuntimeError(f"hash mismatch: {path}: {actual} != {expected}")


def json_write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def elf_symbols(path):
    """Read defined global ELF64 symbols; no target binary tools are used."""
    data = path.read_bytes()
    if data[:6] != b"\x7fELF\x02\x01":
        raise RuntimeError(f"not little-endian ELF64: {path}")
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", data)
    if header[2] != 62:
        raise RuntimeError(f"not AMD64 ELF: {path}")
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, header[6] + i * header[11])
                for i in range(header[12])]
    names = []
    for section in sections:
        if section[1] != 2:
            continue
        strings = sections[section[6]]
        strings = data[strings[4]:strings[4] + strings[5]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            name, info, other, index, value, size = struct.unpack_from("<IBBHQQ", data, offset)
            if index and info >> 4 in (1, 2):
                names.append(strings[name:strings.index(b"\0", name)].decode())
    return sorted(set(names))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path, help="completed gcc-direct/configure.py run")
    parser.add_argument("--out", type=Path, help="new evidence directory")
    args = parser.parse_args()
    work = args.work.resolve()
    out = args.out.resolve() if args.out else Path(tempfile.mkdtemp(prefix="configure-audit-", dir=ROOT / "build-out"))
    if args.out:
        out.mkdir(parents=True, exist_ok=False)
    frozen = json.loads((work / "toolchain-inputs.json").read_text())
    for name, digest in frozen.items():
        verify(work / "toolchain" / name, digest)
    source = json.loads((work / "gcc-source-inputs.json").read_text())
    if source["archive_sha256"] != ARCHIVE_SHA:
        raise RuntimeError("unexpected GCC archive pin")
    verify(Path(source["archive"]), ARCHIVE_SHA)
    command = json.loads((work / "configure-command.json").read_text())
    source_root = Path(command["command"][1]).parent.parent
    for name, digest in source["files"].items():
        path = source_root / name
        if isinstance(digest, str):
            verify(path, digest)
        elif not path.is_symlink() or os.readlink(path) != digest["symlink"]:
            raise RuntimeError(f"symlink mismatch: {path}")
    inventory = json.loads((work / "probe-inventory.json").read_text())
    probes = []
    for number, item in enumerate(inventory):
        trace = work / item["trace"]
        verify(trace / "stdout", item["stdout_sha256"])
        verify(trace / "stderr", item["stderr_sha256"])
        for entry in item["inputs"] + item["outputs"]:
            verify(trace / entry["copy"], entry["sha256"])
        c_inputs = [entry for entry in item["inputs"] if entry["copy"].endswith(".c")]
        c_source = "\n".join((trace / entry["copy"]).read_text() for entry in c_inputs)
        body = c_source.split("/* end confdefs.h.  */")[-1]
        probes.append({"number": number, "trace": item["trace"], "returncode": item["returncode"],
                       "arguments": item["arguments"], "body": body,
                       "diagnostic": (trace / "stderr").read_text(),
                       "input_sha256": {e["copy"]: e["sha256"] for e in item["inputs"]},
                       "output_sha256": {e["copy"]: e["sha256"] for e in item["outputs"]}})
    json_write(out / "verified-probes.json", probes)

    executions = []
    def execute(name, argv, cwd):
        result = subprocess.run(list(map(str, argv)), cwd=cwd, capture_output=True, timeout=60)
        prefix = out / name
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        entry = {"name": name, "command": list(map(str, argv)), "cwd": str(cwd),
                 "returncode": result.returncode, "stdout": result.stdout.decode(errors="replace"),
                 "stderr": result.stderr.decode(errors="replace")}
        executions.append(entry)
        return result

    sizes = []
    for probe, original in zip(probes, inventory):
        match = re.search(r"long longval \(\) \{ return \(long\) \(sizeof \(([^)]+)\)\); \}", probe["body"])
        if not match or original["returncode"]:
            continue
        replay = out / ("sizeof-" + match[1].replace(" ", "_").replace("*", "pointer"))
        replay.mkdir()
        binary = work / original["trace"] / original["outputs"][0]["copy"]
        result = execute(replay.name, [binary], replay)
        sizes.append({"type": match[1], "trace": original["trace"], "returncode": result.returncode,
                      "value": (replay / "conftest.val").read_text() if (replay / "conftest.val").exists() else None,
                      "binary_sha256": sha(binary)})

    driver = work / "toolchain/tools/gcc-direct-cc.py"
    fixture = ROOT / "tests/gcc/configure-audit-layout.c"
    copied = out / fixture.name
    copied.write_bytes(fixture.read_bytes())
    executable = out / "layout"
    compiled = execute("layout-compile", [driver, copied, "-o", executable], out)
    if compiled.returncode:
        raise RuntimeError("audit layout fixture failed; inspect retained diagnostics")
    layout = execute("layout-run", [executable], out)
    expected = ("sizes 1 2 4 8 8 8\nalignments 2 4 8 8 8\nbytes 8 1 1 0\n"
                "stat 144 8 24 48 72\ntypes 4 0 8 1 4 1\n")
    if layout.returncode != 0 or layout.stdout.decode() != expected or layout.stderr:
        raise RuntimeError("unexpected layout/macros; inspect retained output")

    # Diagnostic variants localize failures; they never replace configure input.
    selected = (("endian", "From Harbison&Steele", "void exit(int);\n"),
                ("mkdir", 'mkdir ("foo", 0)', "int mkdir(const char *, unsigned int);\n"))
    diagnostics = []
    for name, needle, declaration in selected:
        matches = [(p, o) for p, o in zip(probes, inventory) if needle in p["body"]]
        if len(matches) != 1:
            raise RuntimeError(f"expected one {name} probe")
        probe, original = matches[0]
        original_source = next(e for e in original["inputs"] if e["copy"].endswith(".c"))
        path = out / (name + "-declared.c")
        path.write_bytes(declaration.encode() + (work / original["trace"] / original_source["copy"]).read_bytes())
        output = out / (name + "-declared" + (".o" if name == "mkdir" else ""))
        argv = [driver, path, "-o", output]
        if name == "mkdir":
            argv.insert(1, "-c")
        result = execute(name + "-declared-compile", argv, out)
        status = None
        if name == "endian" and result.returncode == 0:
            status = execute(name + "-declared-run", [output], out).returncode
        diagnostics.append({"name": name, "original_trace": original["trace"],
                            "original_status": original["returncode"], "variant_status": result.returncode,
                            "variant_execution_status": status, "variant_source_sha256": sha(path)})

    caches = list((work / "toolchain/build-out/gcc-direct-cache").glob("*/manifest.json"))
    # Configure retains its orchestration and archive adapter alongside the
    # C compiler. Those files were verified above, but do not enter the C
    # runtime cache key. Keep this exclusion explicit: a new snapshot input
    # requires a fresh audit of which producer consumes it.
    orchestration = {"gcc-direct/configure.py", "gcc-direct/replay.py",
                     "tools/gcc-direct-ar.py", "gcc-direct/patches/alloca-frame.patch",
                     "gcc-direct/patches/alloca-frame.json"}
    compiler_inputs = {k: v for k, v in frozen.items() if k not in orchestration}
    symbols = {}
    for manifest in caches:
        cache = json.loads(manifest.read_text())
        if cache["source_sha256"] != compiler_inputs:
            raise RuntimeError("runtime cache differs from frozen toolchain")
        for name, digest in cache["artifact_sha256"].items():
            path = manifest.parent / name
            verify(path, digest)
            symbols[name] = {"sha256": digest, "defined_global_symbols": elf_symbols(path)}
    if len(caches) != 1:
        raise RuntimeError("expected one frozen runtime cache")

    exported = {name for obj in symbols.values() for name in obj["defined_global_symbols"]}
    missing_symbols = []
    declaration_failures = []
    for probe in probes:
        if probe["returncode"] == 253:
            names = sorted(set(re.findall(r"char\s+(\w+)\s*\(\s*\)", probe["body"])))
            missing_symbols.append({"trace": probe["trace"], "names": names,
                                    "present_in_runtime": sorted(set(names) & exported)})
        if probe["returncode"] == 143:
            names = re.findall(r"#undef HAVE_DECL_(\w+)", probe["body"])
            if names:
                name = names[0].lower()
                declaration_failures.append({"trace": probe["trace"], "name": name,
                                             "symbol_present_in_runtime": name in exported})

    retained = [work / name for name in ("configure.log", "configure-command.json", "report.json",
                "probe-inventory.json", "toolchain-inputs.json", "gcc-source-inputs.json",
                "host-tool-attempts.jsonl", "build/gcc/auto-host.h", "build/gcc/Makefile", "build/gcc/config.log")]
    report = {"status": "audited provisional run; configuration is not accepted as faithful",
              "original_work": str(work), "gcc_archive_sha256": ARCHIVE_SHA,
              "gcc_source_entries_verified": len(source["files"]),
              "frozen_toolchain_sha256": frozen, "invocation_count": len(inventory),
              "returncodes": dict(sorted(Counter(p["returncode"] for p in inventory).items())),
              "retained_sha256": {str(p.relative_to(work)): sha(p) for p in retained},
              "original_size_executions": sizes, "layout_stdout": layout.stdout.decode(),
              "layout_source_sha256": sha(copied), "layout_binary_sha256": sha(executable),
              "diagnostic_variants": diagnostics, "runtime_object_symbols": symbols,
              "unresolved_symbol_checks": missing_symbols,
              "declaration_syntax_failures": declaration_failures,
              "executions": executions, "audit_script_sha256": sha(Path(__file__)),
              "host_target_code_producers": False}
    json_write(out / "report.json", report)
    print(out / "report.json")
    print("Verified source, traces, replayed sizes and independent LP64/little-endian layout; configuration remains provisional.")


if __name__ == "__main__":
    main()
