#!/usr/bin/env python3
"""Build and run a freestanding program with one command of the Forth-built GCC.

Usage:
    python3 tests/gcc/e2e-freestanding-check.py [WORK] [--out DIR]

WORK is a gcc-direct/driver.py work directory (default: $GCC_DIRECT_DRIVER_WORK,
else build-out/driver).  Without WORK/toolchain/gcc the check prints SKIP and
exits 77.

In a fresh directory, with an environment holding nothing but
PATH=WORK/toolchain, it runs exactly

    gcc -BWORK/toolchain/ -O2 -nostdlib -static e2e-freestanding-hello.c -o hello

so the original GCC 4.0.4 driver runs our cc1, our as and (through our
collect2) our ld.  The program talks to Linux directly; it must print two
lines and exit 42.  Host-tool isolation is checked three ways: the commands
`-v` reports must all live in WORK/toolchain; when strace exists, every
successful execve of the build must too; and WORK/gcc's configure guard log
must not grow.  No installed tool may contain the guard directory's path.

Optional oracle, reported but never failing: our `as` and the host `as`
assemble the same `-S` output, and their .text bytes are compared.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HELLO = ROOT / "tests/gcc/e2e-freestanding-hello.c"
EXPECTED_STDOUT = b"hello from a GCC built by Forth\n6765\n"
EXPECTED_STATUS = 42
REQUIRED = ("gcc", "cc1", "collect2", "as", "ld")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def text_section(path):
    """Bytes of the .text section of an ELF64 little-endian object."""
    data = Path(path).read_bytes()
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    headers = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize) for i in range(shnum)]
    names = headers[shstrndx]
    for header in headers:
        start = names[4] + header[0]
        if data[start:data.index(b"\0", start)] == b".text":
            return data[header[4]:header[4] + header[5]]
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("work", type=Path, nargs="?",
                        default=Path(os.environ.get("GCC_DIRECT_DRIVER_WORK", ROOT / "build-out/driver")))
    parser.add_argument("--out", type=Path, help="new directory for the build (default: fresh under build-out/)")
    args = parser.parse_args()
    work = args.work.resolve()
    tools = work / "toolchain"
    missing = [name for name in REQUIRED if not os.access(tools / name, os.X_OK)]
    if missing:
        print(f"SKIP: no driver toolchain at {tools} (missing {', '.join(missing)}); run gcc-direct/driver.py")
        return 77
    if args.out:
        out = args.out.resolve()
        out.mkdir(parents=True)
    else:
        (ROOT / "build-out").mkdir(exist_ok=True)
        out = Path(tempfile.mkdtemp(prefix="e2e-freestanding-", dir=ROOT / "build-out"))
    guard_log = work / "gcc/host-tool-attempts.jsonl"
    guard_dir = work / "gcc/guard"
    guard_before = guard_log.read_bytes() if guard_log.is_file() else b""
    shutil.copyfile(HELLO, out / "hello.c")
    environment = {"PATH": str(tools)}
    flags = [f"-B{tools}/", "-O2", "-nostdlib", "-static", "hello.c"]
    command = ["gcc", *flags, "-o", "hello"]
    failures = []
    result = {"work": str(work), "toolchain": str(tools), "out": str(out),
              "command": "env -i PATH=" + str(tools) + " " + " ".join(command),
              "tools": {p.name: sha(p) for p in sorted(tools.iterdir()) if p.is_file()}}

    def run(argv, name):
        completed = subprocess.run(argv, cwd=out, env=environment, capture_output=True)
        (out / f"{name}.stdout").write_bytes(completed.stdout)
        (out / f"{name}.stderr").write_bytes(completed.stderr)
        return completed

    built = run(command, "build")
    result["build_returncode"] = built.returncode
    result["build_stderr"] = built.stderr.decode(errors="replace")
    if built.returncode or not (out / "hello").is_file():
        failures.append(f"driver command failed ({built.returncode}): {result['build_stderr'].strip()[-400:]}")
    else:
        result["hello_sha256"] = sha(out / "hello")
        ran = subprocess.run(["./hello"], cwd=out, env={}, capture_output=True)
        result.update(run_stdout=ran.stdout.decode(errors="replace"), run_returncode=ran.returncode)
        if ran.stdout != EXPECTED_STDOUT or ran.returncode != EXPECTED_STATUS:
            failures.append(f"hello printed {ran.stdout!r} and exited {ran.returncode}; "
                            f"expected {EXPECTED_STDOUT!r} and {EXPECTED_STATUS}")

    # What the driver says it runs: lines starting " /path" under -v.
    verbose = run(["gcc", "-v", *flags, "-o", "hello-v"], "verbose")
    # A lone path on such a line is an #include search directory, not a command.
    lines = [line.split() for line in verbose.stderr.decode(errors="replace").splitlines() if line.startswith(" /")]
    commands = [words[0] for words in lines if len(words) > 1]
    result["verbose_commands"] = commands
    result["verbose_include_search"] = [words[0] for words in lines if len(words) == 1]
    outside = [c for c in commands if Path(c).parent != tools]
    if verbose.returncode or not any(Path(c).name == "as" for c in commands) \
            or not any(Path(c).name == "collect2" for c in commands):
        failures.append(f"-v run did not show cc1/as/collect2 (exit {verbose.returncode})")
    if outside:
        failures.append("-v names commands outside the toolchain: " + ", ".join(outside))
    if (out / "hello-v").is_file() and (out / "hello").is_file():
        result["verbose_output_identical"] = (out / "hello-v").read_bytes() == (out / "hello").read_bytes()

    # What the kernel says ran: every successful execve under strace.
    strace = shutil.which("strace")
    if strace:
        trace = out / "execve.trace"
        traced = subprocess.run([strace, "-f", "-qq", "-e", "trace=execve", "-o", str(trace),
                                 str(tools / "gcc"), *flags, "-o", "hello-traced"],
                                cwd=out, env=environment, capture_output=True)
        programs = re.findall(r'execve\("([^"]+)".*= 0$', trace.read_text(), re.M)
        result["execve_programs"] = programs
        strays = [p for p in programs if Path(p).parent != tools]
        if traced.returncode or not programs:
            failures.append(f"traced build failed ({traced.returncode})")
        if strays:
            failures.append("executed outside the toolchain: " + ", ".join(strays))
        if {"cc1", "as", "collect2", "ld"} - {Path(p).name for p in programs}:
            failures.append(f"trace lacks cc1/as/collect2/ld: {programs}")
    else:
        result["execve_programs"] = "strace unavailable; not traced"

    guard_after = guard_log.read_bytes() if guard_log.is_file() else b""
    result["guard_log_unchanged"] = guard_after == guard_before
    if guard_after != guard_before:
        failures.append("configure guard log grew: " + guard_after[len(guard_before):].decode(errors="replace"))
    embedded = [name for name in REQUIRED + ("cpp",) if (tools / name).is_file()
                and str(guard_dir).encode() in (tools / name).read_bytes()]
    result["guard_path_embedded_in"] = embedded
    if embedded:
        failures.append("guard path embedded in: " + ", ".join(embedded))

    # Oracle (report only): our as and host as on the same assembly.
    host_as = shutil.which("as")
    oracle = {"host_as": host_as}
    if host_as and run(["gcc", *flags[:2], "-S", "hello.c", "-o", "hello.s"], "assembly").returncode == 0:
        ours = run(["as", "hello.s", "-o", "ours.o"], "ours-as")
        host = subprocess.run([host_as, "hello.s", "-o", "host.o"], cwd=out, capture_output=True)
        if ours.returncode == 0 and host.returncode == 0:
            ours_text, host_text = text_section(out / "ours.o"), text_section(out / "host.o")
            oracle.update(text_bytes=len(ours_text), text_identical=ours_text == host_text,
                          ours_text_sha256=hashlib.sha256(ours_text).hexdigest(),
                          host_text_sha256=hashlib.sha256(host_text).hexdigest())
        else:
            oracle["error"] = f"our as exit {ours.returncode}, host as exit {host.returncode}"
    result["oracle"] = oracle
    result["failures"] = failures
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print("$ " + result["command"])
    print(f"hello: stdout {result.get('run_stdout', '')!r}, exit {result.get('run_returncode')}")
    print("executed: " + ", ".join(Path(p).name for p in (result["execve_programs"]
                                    if isinstance(result["execve_programs"], list) else commands)))
    if "text_identical" in oracle:
        print(f"oracle: .text {oracle['text_bytes']} bytes, identical to host as: {oracle['text_identical']}")
    for failure in failures:
        print("FAIL: " + failure)
    if not failures:
        print(f"PASS: one driver command built and ran a freestanding program with only {tools}")
    print(out / "result.json")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
