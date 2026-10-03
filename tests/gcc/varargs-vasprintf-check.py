#!/usr/bin/env python3
"""Original GCC vasprintf with Forth target artifacts and independent host oracles."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
VASPRINTF_SHA256 = "3e749239083867d756ddb17eefec27905c75b818de968683a8f64412504c98e4"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(arguments):
    result = subprocess.run([str(a) for a in arguments], capture_output=True,
                            text=True, timeout=120)
    if result.returncode:
        raise AssertionError((arguments, result.returncode, result.stdout, result.stderr))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--config-dir", type=Path, required=True)
    args = parser.parse_args()
    upstream = args.source_root.resolve()
    configured = args.config_dir.resolve()
    source = upstream / "libiberty/vasprintf.c"
    config = configured / "config.h"
    assert source.is_file() and config.is_file(), "original GCC source/configuration missing"
    assert sha(source) == VASPRINTF_SHA256, "original GCC 4.0.4 vasprintf source hash mismatch"
    (ROOT / "build-out").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="varargs-vasprintf-", dir=ROOT / "build-out"))
    driver = ROOT / "tools/gcc-direct-cc.py"
    fixture = ROOT / "tests/gcc/varargs-vasprintf.c"
    includes = ["-DHAVE_CONFIG_H", "-I" + str(configured), "-I" + str(upstream / "include")]
    sources = [ROOT / "seed-forth", ROOT / "010-lib.fth", driver,
               *sorted(ROOT.glob("[0-9][0-9][0-9]-cc-*.fth")),
               *sorted((ROOT / "runtime/gcc-seed").rglob("*.c")),
               *sorted((ROOT / "runtime/gcc-seed").rglob("*.h")), fixture, Path(__file__)]
    hashes = {str(p.relative_to(ROOT)): sha(p) for p in sources}
    inputs = [source, config, upstream / "include/ansidecl.h", upstream / "include/libiberty.h"]
    original_hashes = {str(p): sha(p) for p in inputs}
    identity = run([driver, "--print-source-hash"]).stdout.strip()
    obj = work / "vasprintf.o"
    run([driver, "-c", *includes, source, "-o", obj])
    executable = work / "forth-only"
    run([driver, fixture, obj, "-o", executable])
    result = run([executable])
    assert result.stdout.startswith("PASS: original GCC vasprintf "), result.stdout
    executions = [{"kind": "Forth-only production", "stdout": result.stdout,
                   "executable_sha256": sha(executable)}]
    print(result.stdout.strip(), "Forth-only")
    for opt in ("-O0", "-O2"):
        for original in (False, True):
            exe = work / (("original-host" if original else "Forth-object-host") + opt)
            run(["gcc", "-std=c90", opt, "-fno-pie", "-no-pie", *includes,
                 fixture, source if original else obj, "-o", exe])
            actual = run([exe])
            assert actual.stdout == result.stdout, actual.stdout
            executions.append({"kind": exe.name, "stdout": actual.stdout,
                               "executable_sha256": sha(exe)})
            print("PASS:", exe.name)
    assert hashes == {str(p.relative_to(ROOT)): sha(p) for p in sources}, "compiler/runtime changed"
    assert original_hashes == {str(p): sha(p) for p in inputs}, "original input changed"
    assert identity == run([driver, "--print-source-hash"]).stdout.strip()
    report = {"compiler_source_identity": identity, "compiler_runtime_sha256": hashes,
              "original_input_sha256": original_hashes, "original_object_sha256": sha(obj),
              "executions": executions, "production_uses_host_compiler_or_libc": False,
              "scope": "Unmodified vasprintf; bounded integer/string generator formats, no floating formatting"}
    (work / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(work / "report.json")


if __name__ == "__main__":
    main()
