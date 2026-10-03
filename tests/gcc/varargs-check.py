#!/usr/bin/env python3
"""Reconstruct SysV variadic calls using only Forth-produced target bytes."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASE = ["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth"]
INCLUDES = [ROOT / "runtime/gcc-seed/include", ROOT / "tests/gcc"]


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, timeout=60, **kwargs)
    if result.returncode or result.stdout or result.stderr:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + result.stdout.decode(errors="replace")
                         + result.stderr.decode(errors="replace"))
    return result


def forth(modules, driver):
    source = b"\n".join((ROOT / name).read_bytes() for name in modules)
    run([ROOT / "seed-forth"], input=source + b"\n" + driver.encode())


def path_word(name, path):
    return "create " + name + "\n" + "".join(
        f"[lit] {byte} c,\n" for byte in bytes(path) + b"\0")


def compile_object(source, output):
    run([ROOT / "tests/gcc/sysv-object-compile.sh", source, output, *INCLUDES])


def reject(work, name, code, text, prefix=b"varargs: ", include_header=True):
    source = work / (name + ".c")
    output = work / (name + ".o")
    source.write_text(('#include <stdarg.h>\n' if include_header else '') + text + '\n')
    output.write_bytes(b"previous valid artifact\n")
    result = subprocess.run([ROOT / "tests/gcc/sysv-object-compile.sh", source,
                             output, *INCLUDES], capture_output=True, timeout=30)
    if (result.returncode != code or prefix not in result.stderr
            or result.stdout or output.read_bytes() != b"previous valid artifact\n"):
        raise SystemExit(f"negative {name}: {result.returncode}, {result.stdout!r}, {result.stderr!r}")


def main():
    if not (ROOT / "seed-forth").is_file():
        subprocess.run([ROOT / "build.sh"], check=True)
    (ROOT / "build-out").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="varargs-production-", dir=ROOT / "build-out"))
    objects = []
    for name in ("provider", "production"):
        obj = work / (name + ".o")
        compile_object(ROOT / f"tests/gcc/varargs-{name}.c", obj)
        objects.append(obj)
    start = work / "start.o"
    forth(BASE + ["081-cc-object.fth", "122-cc-sysv-runtime.fth"],
          path_word("start-output", start)
          + "cc-sysrt-start-object start-output cc-obj-write bye\n")
    objects.append(start)
    executable = work / "varargs-production"
    driver = "lnk-init\n"
    for index, obj in enumerate(objects):
        driver += path_word(f"object-{index}", obj) + f"object-{index} lnk-add-object\n"
    driver += "create entry-name s, _start\nentry-name [lit] 6 lnk-entry\n"
    driver += path_word("program", executable) + "program lnk-link bye\n"
    forth(BASE + ["140-cc-link.fth"], driver)
    run([executable])
    negatives = [
        ("wrong-list", 246, "int f(int n, ...) { long p; va_start(p,n); return 0; }"),
        ("wrong-last", 246, "int f(int a,int b,...) { va_list p; va_start(p,a); return 0; }"),
        ("fixed-start", 246, "int f(int n) { va_list p; va_start(p,n); return 0; }"),
        ("narrow-arg", 247, "int f(int n,...) { va_list p; va_start(p,n); return va_arg(p,char); }"),
        ("aggregate-arg", 247, "struct T { long x; }; int f(int n,...) { va_list p; va_start(p,n); va_arg(p,struct T); return 0; }"),
        ("array-arg", 247, "int f(int n,...) { va_list p; va_start(p,n); va_arg(p,va_list); return 0; }"),
        ("void-arg", 247, "int f(int n,...) { va_list p; va_start(p,n); va_arg(p,void); return 0; }"),
        ("bad-copy", 246, "int f(int n,...) { va_list p; long q; va_start(p,n); va_copy(q,p); return 0; }"),
        ("bad-end", 246, "int f(int n) { va_end(n); return 0; }"),
    ]
    for name, code, source in negatives:
        reject(work, name, code, source)
    reject(work, "floating-arg", 214,
           "int f(int n,...) { va_list p; va_start(p,n); va_arg(p,double); return 0; }", b"cc: ")
    reject(work, "bad-layout", 246,
           "struct __seed_va_list_tag { unsigned long gp_offset; unsigned int fp_offset; "
           "void *overflow_arg_area; void *reg_save_area; }; "
           "int f(int n,...) { struct __seed_va_list_tag p[1]; __builtin_va_start(p,n); return 0; }",
           include_header=False)
    sources = sorted(set([ROOT / "seed-forth", ROOT / "010-lib.fth",
                          ROOT / "140-cc-link.fth", ROOT / "tests/gcc/sysv-object-compile.sh",
                          ROOT / "runtime/gcc-seed/include/stdarg.h"]
                         + list((ROOT / "tests/gcc").glob("varargs-*"))
                         + [p for p in ROOT.glob("[0-9][0-9][0-9]-cc-*.fth")
                            if p.name not in ("120-cc-main.fth", "140-cc-link.fth")]))
    report = {
        "proof": "Forth compiler, Forth startup object, Forth linker; no host compiler or libc",
        "host_compiler": False,
        "host_linker": False,
        "host_libc": False,
        "negative_cases": len(negatives) + 2,
        "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sources},
        "artifact_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in objects + [executable]},
    }
    (work / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("PASS: source-built integer/pointer varargs production reconstruction")
    print(work / "report.json")


if __name__ == "__main__":
    main()
