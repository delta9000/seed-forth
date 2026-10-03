#!/usr/bin/env python3
"""Forth C + Forth runtime objects + Forth linker, with no host C artifacts."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(command, *, input=None, expected=0):
    result = subprocess.run(command, input=input, capture_output=True)
    if result.returncode != expected:
        raise SystemExit(f"{command}: expected {expected}, got {result.returncode}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


def path_word(name, path):
    return "create " + name + "\n" + "".join(
        f"[lit] {b} c,\n" for b in bytes(path) + b"\0")


def forth(modules, driver):
    source = b"".join((ROOT / p).read_bytes() for p in modules) + driver.encode()
    result = run([str(ROOT / "seed-forth")], input=source)
    if result.stdout or result.stderr:
        raise SystemExit("unexpected Forth output: " + repr(result))


def main():
    work_parent = ROOT / "build-out"
    work_parent.mkdir(exist_ok=True)
    if not (ROOT / "seed-forth").is_file():
        run([str(ROOT / "build.sh")])
    with tempfile.TemporaryDirectory(prefix="syscall-runtime.", dir=work_parent) as t:
        work = Path(t)
        objects = []
        for name, builder in (("syscall", "cc-sysrt-object"),
                              ("errno", "cc-sysrt-errno-object"),
                              ("start", "cc-sysrt-start-object")):
            obj = work / (name + ".o")
            forth(["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth",
                   "081-cc-object.fth", "122-cc-sysv-runtime.fth"],
                  path_word("target", obj) + builder + " target cc-obj-write bye\n")
            objects.append(obj)
        c_source = work / "main.c"
        c_source.write_text("""int *__errno_location(void);
long __seed_syscall6(long, long, long, long, long, long, long);
int main(int argc, char **argv) {
  int *p = __errno_location();
  if (*p) return 1;
  *p = 63;
  if (__errno_location() != p || *__errno_location() != 63) return 2;
  if (argc != 3 || argv[1][0] != 120 || argv[2][0] != 121 || argv[3]) return 3;
  if (__seed_syscall6(39, 0, 0, 0, 0, 0, 0) < 1) return 4;
  if (__seed_syscall6(3, -1, 0, 0, 0, 0, 0) != -9) return 5;
  if (*p != 63) return 6;
  return 42;
}
""")
        main_obj = work / "main.o"
        run(["bash", str(ROOT / "tests/gcc/sysv-object-compile.sh"),
             str(c_source), str(main_obj)])
        objects.append(main_obj)
        exe = work / "program"
        driver = "lnk-init\n"
        for i, obj in enumerate(objects):
            driver += path_word(f"object{i}", obj) + f"object{i} lnk-add-object\n"
        driver += "create entry s, _start\nentry [lit] 6 lnk-entry\n"
        driver += path_word("target", exe) + "target lnk-link bye\n"
        forth(["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth",
               "140-cc-link.fth"], driver)
        run([str(exe), "x", "y"], expected=42)
        print("PASS: Forth C, errno BSS, startup arguments, raw syscalls and Forth link")
        print(json.dumps({p.name: {"bytes": p.stat().st_size,
                                  "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                          for p in [*objects, exe]}, sort_keys=True))


if __name__ == "__main__":
    main()
