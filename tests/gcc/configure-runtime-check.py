#!/usr/bin/env python3
"""Forth-only configure runtime: real files, ABI layout, errno and process exit."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/gcc-seed"
BASE = ["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth"]


def run(command, expected=b"", expected_error=b"", status=0, **kwargs):
    result = subprocess.run(command, capture_output=True, timeout=60, **kwargs)
    if (result.returncode, result.stdout, result.stderr) != (status, expected, expected_error):
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + repr(result.stdout) + "\n" + repr(result.stderr))
    return result


def forth(modules, driver):
    source = b"\n".join((ROOT / name).read_bytes() for name in modules)
    run([ROOT / "seed-forth"], input=source + b"\n" + driver.encode())


def path_word(name, path):
    return "create " + name + "\n" + "".join(
        f"[lit] {byte} c,\n" for byte in os.fsencode(path) + b"\0")


def link(objects, executable):
    driver = "lnk-init\n"
    for index, obj in enumerate(objects):
        driver += path_word(f"object-{index}", obj) + f"object-{index} lnk-add-object\n"
    driver += "create entry-name s, _start\nentry-name [lit] 6 lnk-entry\n"
    driver += path_word("program", executable) + "program lnk-link bye\n"
    forth(BASE + ["140-cc-link.fth"], driver)


def main():
    if not (ROOT / "seed-forth").is_file():
        subprocess.run([ROOT / "build.sh"], check=True)
    (ROOT / "build-out").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="configure-runtime-", dir=ROOT / "build-out"))
    # perror in stdio.c reports through strerror.c (runtime/gcc-seed/ERRNO.md).
    sources = [RUNTIME / (name + ".c") for name in ("memory", "string", "alloc", "strerror", "floatfmt", "stdio", "stat", "process")]
    sources += [ROOT / "tests/gcc" / ("configure-runtime-" + name + ".c")
                for name in ("layout", "production", "exit", "faults")]
    inputs = sorted(set(sources + [Path(__file__).resolve(), ROOT / "seed-forth",
                         ROOT / "010-lib.fth", ROOT / "tests/gcc/sysv-object-compile.sh",
                         ROOT / "tools/compiler-layers.sh"]
                        + list(ROOT.glob("[0-9][0-9][0-9]-cc-*.fth"))
                        + list((RUNTIME / "include").rglob("*.h"))))
    source_hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    objects = {}
    for source in sources:
        obj = work / (source.stem + ".o")
        run([ROOT / "tests/gcc/sysv-object-compile.sh", source, obj, RUNTIME / "include"])
        objects[source.stem] = obj
    driver = ""
    for name, builder in (("syscall", "cc-sysrt-object"),
                          ("errno", "cc-sysrt-errno-object"),
                          ("start", "cc-sysrt-start-object")):
        obj = work / (name + ".o")
        driver += path_word(name + "-output", obj)
        driver += f"{builder} {name}-output cc-obj-write\n"
        objects[name] = obj
    forth(BASE + ["081-cc-object.fth", "122-cc-sysv-runtime.fth"], driver + "bye\n")
    common = [objects[name] for name in ("memory", "string", "alloc", "strerror", "floatfmt", "stdio", "stat", "process", "errno", "start")]
    programs = {}
    for name in ("layout", "production", "exit", "faults"):
        executable = work / name
        linked = [objects["stat"], objects["errno"], objects["start"]] if name == "faults" else common + [objects["syscall"]]
        link(linked + [objects["configure-runtime-" + name]], executable)
        programs[name] = executable
    fixture = work / "sparse-file"
    fixture.write_bytes(b"configure fixture")
    with fixture.open("r+b") as stream:
        stream.truncate((1 << 33) + 17)
    fixture.chmod(0o640)
    os.utime(fixture, ns=(1700000000123456789, -123456788012345679))
    (work / "hard-link").hardlink_to(fixture)
    symbolic = work / "symbolic-link"
    symbolic.symlink_to(fixture.name)
    st = fixture.stat()
    expected = b"".join((f"{name} {size} {signed}\n".encode()) for name, size, signed in (
        ("size_t", 8, 0), ("ssize_t", 8, 1), ("off_t", 8, 1), ("time_t", 8, 1),
        ("blksize_t", 8, 1), ("blkcnt_t", 8, 1), ("dev_t", 8, 0), ("ino_t", 8, 0),
        ("nlink_t", 8, 0), ("mode_t", 4, 0), ("uid_t", 4, 0), ("gid_t", 4, 0), ("pid_t", 4, 1)))
    expected += b"stat 144 8\n"
    expected += b"".join(f"{name} {offset}\n".encode() for name, offset in (
        ("st_dev", 0), ("st_ino", 8), ("st_nlink", 16), ("st_mode", 24), ("st_uid", 28),
        ("st_gid", 32), ("st_rdev", 40), ("st_size", 48), ("st_blksize", 56),
        ("st_blocks", 64), ("st_atime", 72), ("st_mtime", 88), ("st_ctime", 104)))
    expected += b"nanoseconds 80 96 112\nmodes 61440 49152 40960 32768 24576 16384 8192 4096\n"
    fields = (st.st_dev, st.st_ino, st.st_nlink, st.st_mode, st.st_uid, st.st_gid,
              st.st_rdev, st.st_size, st.st_blksize, st.st_blocks,
              st.st_atime_ns // 10**9, st.st_mtime_ns // 10**9, st.st_ctime_ns // 10**9)
    expected += ("file " + " ".join(map(str, fields)) + "\n").encode()
    nanoseconds = (st.st_atime_ns % 10**9, st.st_mtime_ns % 10**9, st.st_ctime_ns % 10**9)
    expected += ("file-ns " + " ".join(map(str, nanoseconds)) + "\n").encode()
    run([programs["layout"], fixture], expected=expected)
    (work / "layout-output.txt").write_bytes(expected)
    read_fd, write_fd = os.pipe()
    try:
        with fixture.open("rb") as stream:
            run([programs["production"], fixture, symbolic, work, work / "missing",
                 str(stream.fileno()), str(read_fd), work / "exit-output"],
                pass_fds=(stream.fileno(), read_fd), expected=b"configure runtime\n",
                expected_error=b"exit diagnostic\n")
    finally:
        os.close(read_fd)
        os.close(write_fd)
    if (work / "exit-output").read_bytes() != b"written before exit\n":
        raise SystemExit("exit lost unbuffered stream output")
    statuses = (0, 1, 42, 255, 256, 511, -1, -256, -257)
    for status in statuses:
        run([programs["exit"], str(status)], status=status & 255, expected=b"before exit\n")
    run([programs["faults"]])
    if any(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != value
           for name, value in source_hashes.items()):
        raise SystemExit("source inputs changed during validation; retry")
    report = {"proof": "Forth-built runtime and clients; Forth ABI objects/linker; real Linux syscalls",
              "host_compiler": False, "host_assembler": False, "host_linker": False, "host_libc": False,
              "abi_reference": "Linux v6.12 AMD64 syscall ABI; independent Python os.stat real-file comparison",
              "exit_statuses": list(statuses), "artifacts": str(work),
              "source_sha256": source_hashes,
              "artifact_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in list(objects.values()) + list(programs.values())}}
    (work / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("PASS: configure runtime ABI, real-file stat/fstat, errno, exit and syscall-error boundaries")
    print(work / "report.json")


if __name__ == "__main__":
    main()
