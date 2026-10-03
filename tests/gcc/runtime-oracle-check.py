#!/usr/bin/env python3
"""Optional host-libc differential oracle, separate from production closure."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/gcc-seed"
NAMES = ("memcpy memmove memset memcmp memchr strlen strcmp strncmp strcpy "
         "strncpy strcat strncat strchr strrchr strstr strdup malloc free calloc realloc").split()


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, timeout=120, **kwargs)
    if result.returncode:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


def main():
    cc = shutil.which("gcc")
    if not cc:
        print("SKIP: host gcc is required only for the optional differential oracle")
        raise SystemExit(77)
    (ROOT / "build-out").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="runtime-oracle-", dir=ROOT / "build-out") as tmp:
        work = Path(tmp)
        # Namespace the Forth-built copies so the host's libc stays independent.
        prefix = "".join(f"#define {name} seed_{name}\n" for name in NAMES)
        prefix += "#define __errno_location seed_errno_location\n"
        objects = []
        for name in ("memory", "string", "alloc"):
            source = work / (name + ".c")
            source.write_text(prefix + (RUNTIME / (name + ".c")).read_text())
            obj = work / (name + ".o")
            run([ROOT / "tests/gcc/sysv-object-compile.sh", source, obj, RUNTIME / "include"])
            objects.append(obj)
        syscall = work / "syscall.o"
        pathname = "create syscall-output\n" + "".join(
            f"[lit] {byte} c,\n" for byte in bytes(syscall) + b"\0")
        driver = pathname + "cc-sysrt-object syscall-output cc-obj-write bye\n"
        modules = ("010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth",
                   "081-cc-object.fth", "122-cc-sysv-runtime.fth")
        forth = b"\n".join((ROOT / name).read_bytes() for name in modules)
        run([ROOT / "seed-forth"], input=forth + b"\n" + driver.encode())
        for optimization in ("-O0", "-O2"):
            executable = work / ("oracle" + optimization[1:])
            run([cc, "-std=c99", "-Wall", "-Wextra", "-Werror", optimization,
                 "-fno-builtin", "-fno-pie", "-no-pie", "-Wl,-z,noexecstack",
                 ROOT / "tests/gcc/runtime-oracle.c", *objects, syscall, "-o", executable])
            print(run([executable]).stdout.decode().strip(), optimization)
        print("Oracle only: host GCC, host linker and host libc are used by this check.")


if __name__ == "__main__":
    main()
