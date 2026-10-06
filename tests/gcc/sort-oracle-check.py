#!/usr/bin/env python3
"""Host GCC/libc oracle for a retained sort-check.py production snapshot."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command):
    result = subprocess.run(command, capture_output=True, timeout=120)
    if result.returncode or result.stderr:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work", type=Path, help="retained production work directory")
    args = parser.parse_args()
    cc = shutil.which("gcc")
    if not cc:
        print("SKIP: host GCC is needed only for the separate oracle")
        raise SystemExit(77)
    work = args.work.resolve()
    proof = json.loads((work / "report.json").read_text())
    frozen = work / "source"
    for name, expected in proof["source_sha256"].items():
        assert sha(frozen / name) == expected, "frozen input changed: " + name
    for name, expected in proof["artifact_sha256"].items():
        assert sha(work / name) == expected, "production artifact changed: " + name
    oracle = work / "oracle"
    oracle.mkdir(exist_ok=True)
    source = oracle / "seed-sort.c"
    # qsort.c's memcpy calls bind to the host libc's memcpy in this oracle link.
    runtime = (frozen / "runtime/gcc-seed/sort.c").read_text() + (frozen / "runtime/gcc-seed/qsort.c").read_text()
    source.write_text("#define qsort seed_qsort\n#define bsearch seed_bsearch\n" + runtime)
    host_source = oracle / "host-seed-sort.c"
    host_source.write_text(runtime)
    forth_object = oracle / "seed-sort.o"
    run([frozen / "tests/gcc/sysv-object-compile.sh", source, forth_object,
         frozen / "runtime/gcc-seed/include"])
    runs = {}
    for optimization in ("-O0", "-O2"):
        host_object = oracle / ("host-sort" + optimization[1:] + ".o")
        executable = oracle / ("oracle" + optimization[1:])
        flags = ["-std=c99", "-Wall", "-Wextra", "-Werror", "-fno-builtin",
                 "-fno-pie", "-fsanitize=undefined", "-fno-sanitize-recover=all", optimization]
        # musl's smoothsort compares int shift counts with size_t and parks a
        # local buffer's address in its caller's array; both are intended.
        run([cc, *flags, "-Wno-sign-compare", "-Wno-dangling-pointer",
             "-Dqsort=host_seed_qsort", "-Dbsearch=host_seed_bsearch", "-c",
             host_source, "-o", host_object])
        run([cc, *flags, "-no-pie", "-Wl,-z,noexecstack",
             frozen / "tests/gcc/sort-oracle.c", forth_object, host_object, "-o", executable])
        result = run([executable])
        print(result.stdout.decode().strip(), optimization)
        runs[optimization] = {"returncode": result.returncode,
                              "stdout": result.stdout.decode(),
                              "executable_sha256": sha(executable),
                              "host_object_sha256": sha(host_object)}
    assert all(sha(frozen / name) == expected for name, expected in proof["source_sha256"].items())
    report = {"oracle_only": True, "host_compiler": cc, "host_libc": True,
              "host_undefined_behavior_sanitizer": True,
              "production_manifest": str(work / "report.json"),
              "forth_namespaced_object_sha256": sha(forth_object), "runs": runs}
    (oracle / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("Oracle only: host GCC, linker and libc are separate from production.")
    print(oracle / "report.json")


if __name__ == "__main__":
    main()
