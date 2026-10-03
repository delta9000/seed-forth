#!/usr/bin/env python3
"""Create fresh generator build trees from recorded configuration and new sources.

No configure answers are added or edited. All prior target objects, archives and
known generator executables are omitted. The retained original configure command,
probe inventory and configured header bytes identify the older configuration
compiler; explicit make overrides identify the new build compiler.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import shlex
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gcc_work", type=Path)
    parser.add_argument("libiberty_work", type=Path)
    parser.add_argument("--compiler-root", type=Path, default=ROOT)
    args = parser.parse_args()
    compiler = args.compiler_root.resolve()
    spec = importlib.util.spec_from_file_location("direct_configure", compiler / "gcc-direct/configure.py")
    recipe = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(recipe)
    work = Path(tempfile.mkdtemp(prefix="direct-generator-replay-", dir=ROOT / "build-out"))
    snapshot = recipe.snapshot(work)
    compiler_hashes = json.loads((work / "toolchain-inputs.json").read_text())
    result = {"scope": "Fresh build using recorded older configuration; configure is not rerun", "work": str(work),
              "replay_script_sha256": sha(Path(__file__))}
    for component, original in (("gcc", args.gcc_work.resolve()), ("libiberty", args.libiberty_work.resolve())):
        report = json.loads((original / "report.json").read_text())
        assert report["component"] == component and report["returncode"] == 0
        target = work / component
        target.mkdir()
        for name in ("configure-command.json", "gcc-source-inputs.json", "probe-inventory.json", "alloca-adapter.json"):
            if (original / name).is_file():
                shutil.copy2(original / name, target / name)
        shutil.copytree(snapshot, target / "toolchain")
        save(target / "toolchain-inputs.json", compiler_hashes)
        oldbuild, newbuild = original / "build" / component, target / "build" / component
        shutil.copytree(oldbuild, newbuild,
                        ignore=shutil.ignore_patterns("*.o", "*.a", "genmodes", "gencheck-direct", "gencheck", "gengenrtl", "gengenrtl-direct"))
        headers = {str(p.relative_to(oldbuild)): sha(p) for p in oldbuild.rglob("*.h") if p.is_file()}
        assert all(sha(newbuild / name) == expected for name, expected in headers.items())
        (target / "probes").mkdir()
        cc = shlex.join([sys.executable, str(target / "toolchain/gcc-direct/configure.py"), "--invoke",
                         str(target / "toolchain/tools/gcc-direct-cc.py"), str(target / "probes")])
        ar = shlex.join([sys.executable, str(target / "toolchain/tools/gcc-direct-ar.py")])
        overrides = {"CC": cc, "CPP": cc + " -E", "CC_FOR_BUILD": cc, "AR": ar, "RANLIB": ar + " s"}
        reuse = {"original_work": str(original), "configure_was_rerun": False,
                 "configure_command_sha256": sha(original / "configure-command.json"),
                 "configure_report_sha256": sha(original / "report.json"),
                 "configure_probes_sha256": sha(original / "probe-inventory.json"),
                 "configured_header_sha256": headers,
                 "configuration_compiler": json.loads((original / "toolchain-inputs.json").read_text()),
                 "build_compiler": compiler_hashes, "build_environment": overrides, "make_overrides": overrides}
        save(target / "configuration-reuse.json", reuse)
        report.update({"configuration_reused_from": str(original), "configure_was_rerun": False,
                       "work": str(target), "compiler": "New frozen build compiler; original configuration compiler retained in configuration-reuse.json"})
        save(target / "report.json", report)
        result[component] = str(target)
    save(work / "replay.json", result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
