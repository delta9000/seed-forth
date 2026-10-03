#!/usr/bin/env python3
"""Independently replay the original C-only gencheck diagnostic, without accepting configure."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
helpers = runpy.run_path(str(ROOT / "tests/gcc/configure-audit-check.py"))
sha, verify, json_write = (helpers[key] for key in ("sha", "verify", "json_write"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    out = Path(tempfile.mkdtemp(prefix="configure-audit-gencheck-", dir=ROOT / "build-out"))
    command = json.loads((work / "configure-command.json").read_text())
    source = Path(command["command"][1]).parent
    build = work / "build/gcc"
    manifest = json.loads((work / "gcc-source-inputs.json").read_text())
    verify(Path(manifest["archive"]), helpers["ARCHIVE_SHA"])
    for name, digest in manifest["files"].items():
        if isinstance(digest, str):
            verify(source.parent / name, digest)
    for name, digest in json.loads((work / "toolchain-inputs.json").read_text()).items():
        verify(work / "toolchain" / name, digest)
    configured = (build / "Makefile").read_text()
    if "--enable-languages=c" not in command["command"]:
        raise RuntimeError("this audit requires original C-only configuration")
    if not re.search(r"^lang_tree_files=\s*$", configured, re.M):
        raise RuntimeError("unexpected additional language tree inputs")
    if (build / "gencheck.h").read_bytes() != b"":
        raise RuntimeError("C-only original Makefile gencheck.h must be empty")
    if (source / ".-tree.def").exists():
        raise RuntimeError("unexpected base-directory language tree input")
    declarations = {}
    for config in source.glob("*/config-lang.in"):
        match = re.search(r'^language=[\'\"]?([^\s\'\"]+)', config.read_text(), re.M)
        if match:
            declarations[str(config.relative_to(source))] = match[1]
    if "c" in declarations.values():
        raise RuntimeError("additional C language directory needs explicit auditing")

    generated = {str(path.relative_to(build)): sha(path) for path in build.rglob("*.h")}
    for name in generated:
        destination = out / "generated" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes((build / name).read_bytes())
    traces = []
    for path in (work / "probes").glob("*/invocation.json"):
        item = json.loads(path.read_text())
        if "-c" in item["arguments"] and str(source / "gencheck.c") in item["arguments"]:
            traces.append((path, item))
    if not traces:
        raise RuntimeError("original Makefile gencheck object invocation not retained")
    traces.sort()
    original_trace, invocation = traces[0]
    if invocation["returncode"]:
        raise RuntimeError("retained original generator did not compile")
    for item in invocation["inputs"] + invocation["outputs"]:
        verify(original_trace.parent / item["copy"], item["sha256"])

    obj = out / "gencheck.o"
    exe = out / "gencheck"
    argv = list(invocation["arguments"])
    argv[argv.index("-o") + 1] = str(obj)
    executions = []
    def execute(name, arguments, expected_status=0):
        result = subprocess.run(list(map(str, arguments)), cwd=build, capture_output=True, timeout=60)
        (out / (name + ".stdout")).write_bytes(result.stdout)
        (out / (name + ".stderr")).write_bytes(result.stderr)
        executions.append({"name": name, "arguments": list(map(str, arguments)),
                           "cwd": str(build), "returncode": result.returncode,
                           "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
                           "stderr": result.stderr.decode(errors="replace")})
        if result.returncode != expected_status:
            raise RuntimeError(f"unexpected status for {name}: {result.returncode}")
        return result
    driver = work / "toolchain/tools/gcc-direct-cc.py"
    execute("compile", [driver, *argv])
    verify(obj, invocation["outputs"][0]["sha256"])
    execute("link", [driver, obj, "-o", exe])
    report = json.loads((work / "gencheck-report.json").read_text())
    verify(exe, report["executable_sha256"])
    result = execute("run", [exe])
    usage = execute("usage", [exe, "unexpected"], 1)
    if usage.stdout or usage.stderr != b"Usage: gencheck\n":
        raise RuntimeError("unexpected usage behavior")

    codes = []
    definition_inputs = {}
    for name in ("tree.def", "c-common.def"):
        path = source / name
        data = path.read_text()
        data = re.sub(r"/\*.*?\*/", "", data, flags=re.S)
        if re.search(r"^\s*#", data, re.M):
            raise RuntimeError("conditional .def input needs explicit interpretation")
        names = re.findall(r"\bDEFTREECODE\s*\(\s*([A-Za-z_][A-Za-z_0-9]*)\s*,", data)
        definition_inputs[name] = {"sha256": sha(path), "count": len(names)}
        for name in names:
            if name not in codes:
                codes.append(name)
    expected = ("/* This file is generated using gencheck. Do not edit. */\n\n"
                "#ifndef GCC_TREE_CHECK_H\n#define GCC_TREE_CHECK_H\n\n")
    expected += "".join(f"#define {code}_CHECK(t)\tTREE_CHECK (t, {code})\n" for code in codes)
    expected += "\n#endif /* GCC_TREE_CHECK_H */\n"
    if result.stdout != expected.encode() or result.stderr:
        raise RuntimeError("generator output differs from independently read original definitions")
    for name, digest in generated.items():
        verify(build / name, digest)
    json_write(out / "report.json", {
        "status": "original gencheck output reproduced; original configuration remains provisional",
        "archive_sha256": manifest["archive_sha256"], "original_work": str(work),
        "original_trace": str(original_trace.relative_to(work)),
        "audit_script_sha256": sha(Path(__file__)), "generated_header_sha256": generated,
        "original_source_sha256": {name: sha(source / name) for name in
          ("gencheck.c", "tree.def", "c-common.def", "configure", "Makefile.in", "mkconfig.sh")},
        "source_manifest_sha256": sha(work / "gcc-source-inputs.json"),
        "toolchain_manifest_sha256": sha(work / "toolchain-inputs.json"),
        "configured_makefile_sha256": sha(build / "Makefile"),
        "language_directories": declarations, "lang_tree_files": "", "gencheck_h_bytes": 0,
        "definition_inputs": definition_inputs, "unique_tree_codes": len(codes),
        "object_sha256": sha(obj), "executable_sha256": sha(exe),
        "output_sha256": hashlib.sha256(result.stdout).hexdigest(), "output_bytes": len(result.stdout),
        "executions": executions, "host_target_code_producers": False,
        "scope": "Original Makefile object flags replayed; bounded runtime focused link omits BUILD_LIBIBERTY. No archive/full Makefile link/full GCC proof."
    })
    print(out / "report.json")


if __name__ == "__main__":
    main()
