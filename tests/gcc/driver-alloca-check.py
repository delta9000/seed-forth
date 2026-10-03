#!/usr/bin/env python3
"""Validate the explicit C_alloca target adapter without changing upstream.

Pass a coherent compiler root containing the frame helper/header and a retained
original libiberty configure work directory. All target artifacts use Forth.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, capture_output=True, timeout=60)
    assert result.returncode == 0 and not result.stdout and not result.stderr, (command, result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler_root", type=Path)
    parser.add_argument("libiberty_work", type=Path)
    args = parser.parse_args()
    compiler = args.compiler_root.resolve()
    configured = args.libiberty_work.resolve()
    config = json.loads((configured / "configure-command.json").read_text())
    source = Path(config["command"][1]).parent.parent
    if (configured / "alloca-adapter.json").is_file():
        source = Path(json.loads((configured / "alloca-adapter.json").read_text())["original_source"])
    work = Path(tempfile.mkdtemp(prefix="alloca-adapter-", dir=ROOT / "build-out"))
    module = importlib.util.spec_from_file_location("direct_recipe", ROOT / "gcc-direct/configure.py")
    recipe = importlib.util.module_from_spec(module)
    module.loader.exec_module(recipe)
    view = recipe.prepare_alloca_source(source, work)
    cc = compiler / "tools/gcc-direct-cc.py"
    include_flags = ["-DHAVE_CONFIG_H", "-I" + str(configured / "build/libiberty"),
                     "-I" + str(view / "include")]
    for name in ("alloca", "xmalloc", "xexit"):
        run([cc, "-c", *include_flags, view / "libiberty" / (name + ".c"), "-o", work / (name + ".o")], work)
    fixture = ROOT / "tests/gcc/driver-alloca-lifetime.c"
    executable = work / "production"
    run([cc, fixture, work / "alloca.o", work / "xmalloc.o", work / "xexit.o", "-o", executable], work)
    run([executable], work)
    identity = subprocess.check_output([cc, "--print-source-hash"]).decode().strip()
    cache = compiler / "build-out/gcc-direct-cache" / identity
    cache_manifest = json.loads((cache / "manifest.json").read_text())
    helpers = []
    for name in ("start.o", "syscall.o", "frame.o"):
        assert sha(cache / name) == cache_manifest["artifact_sha256"][name]
        helpers.append(cache / name)
    observer = work / "observed"
    run([cc, "-nostdlib", "-DOBSERVE_FREES", fixture, ROOT / "tests/gcc/driver-alloca-observer.c",
         work / "alloca.o", *helpers, "-o", observer], work)
    run([observer], work)
    report = {"scope": "Original C_alloca with explicit __SEED_FORTH__ stable-frame adapter; original algorithm retained",
              "source_archive_sha256": json.loads((configured / "report.json").read_text())["gcc_source_sha256"],
              "adapter": json.loads((work / "alloca-adapter.json").read_text()),
              "compiler_source_identity": identity, "compiler_source_sha256": cache_manifest["source_sha256"],
              "configuration_sha256": sha(configured / "build/libiberty/config.h"),
              "original_sources": {name: sha(source / "libiberty" / (name + ".c")) for name in ("alloca", "xmalloc", "xexit")},
              "production": "same-frame, nested argument, callback and recursive lifetimes pass using actual allocator/abort",
              "observation": "Separate test allocator:13 allocations/13 frees, no premature/double/unknown free",
              "artifacts": {path.name: sha(path) for path in [work / "alloca.o", work / "xmalloc.o", work / "xexit.o", executable, observer]},
              "host_target_tools": False}
    (work / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("PASS: faithful C_alloca caller lifetimes and actual deeper-frame reclamation")
    print(work / "report.json")


if __name__ == "__main__":
    main()
