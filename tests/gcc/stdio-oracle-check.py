#!/usr/bin/env python3
"""Compare Forth-built formatting against independent host libc at O0/O2."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/gcc-seed"
NAMES = ("fopen fdopen freopen fclose fflush ferror feof clearerr fwrite fread fputc putc putchar "
         "fputs puts fgetc getc getwc getchar fgets ungetc ftell fseek fileno vfprintf fprintf vprintf printf "
         "vsnprintf snprintf vsprintf sprintf perror setvbuf setbuffer setlinebuf fseeko ftello getc_unlocked "
         "getchar_unlocked putc_unlocked putchar_unlocked flockfile ftrylockfile funlockfile").split()


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
        print("SKIP: host GCC is needed only by this independent oracle")
        raise SystemExit(77)
    (ROOT / "build-out").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="stdio-oracle-", dir=ROOT / "build-out"))
    source = RUNTIME / "stdio.c"
    includes = [RUNTIME / "include"]
    renamed = work / "stdio.c"
    renamed.write_text("".join(f"#define {name} seed_{name}\n" for name in NAMES)
                       + source.read_text())
    obj = work / "stdio.o"
    run([ROOT / "tests/gcc/sysv-object-compile.sh", renamed, obj, *includes])
    floating = work / "floatfmt.o"
    run([ROOT / "tests/gcc/sysv-object-compile.sh", RUNTIME / "floatfmt.c", floating, *includes])
    syscall = work / "syscall.o"
    driver = "create syscall-output\n" + "".join(
        f"[lit] {byte} c,\n" for byte in bytes(syscall) + b"\0")
    driver += "cc-sysrt-object syscall-output cc-obj-write bye\n"
    modules = ("010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth",
               "081-cc-object.fth", "122-cc-sysv-runtime.fth")
    forth = b"\n".join((ROOT / name).read_bytes() for name in modules)
    run([ROOT / "seed-forth"], input=forth + b"\n" + driver.encode())
    for optimization in ("-O0", "-O2"):
        executable = work / ("oracle" + optimization[1:])
        run([cc, "-std=c99", "-Wall", "-Wextra", "-Werror", optimization, "-U_FORTIFY_SOURCE",
             "-fno-builtin", "-fno-pie", "-no-pie", "-Wl,-z,noexecstack",
             ROOT / "tests/gcc/stdio-oracle.c", obj, floating, syscall, "-o", executable])
        print(run([executable]).stdout.decode().strip(), optimization)
    print("Oracle only: host GCC/linker/libc; the compared seed stdio object is Forth-built.")
    print(work)


if __name__ == "__main__":
    main()
