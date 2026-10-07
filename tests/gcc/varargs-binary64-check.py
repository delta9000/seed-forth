#!/usr/bin/env python3
"""Forth-generated binary64 va_arg callees; host callers are test oracles only."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(arguments, expected=0):
    result = subprocess.run([str(a) for a in arguments], capture_output=True,
                            text=True, timeout=120)
    if result.returncode != expected:
        raise AssertionError((arguments, result.returncode, result.stdout, result.stderr))
    return result


def main():
    (ROOT / "build-out").mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="varargs-binary64-", dir=ROOT / "build-out"))
    compile = ROOT / "tests/gcc/sysv-object-compile.sh"
    sources = [ROOT / "seed-forth", ROOT / "010-lib.fth", compile,
               *sorted(ROOT.glob("[0-9][0-9][0-9]-cc-*.fth")),
               ROOT / "runtime/gcc-seed/include/stdarg.h",
               ROOT / "tests/gcc/varargs-binary64.c",
               ROOT / "tests/gcc/varargs-binary64-oracle.c", Path(__file__)]
    hashes = {str(p.relative_to(ROOT)): sha(p) for p in sources}
    obj = work / "callee.o"
    run([compile, ROOT / "tests/gcc/varargs-binary64.c", obj,
         ROOT / "runtime/gcc-seed/include"])
    executions = []
    for opt in ("-O0", "-O2"):
        exe = work / ("host" + opt)
        run(["gcc", "-std=c99", opt, "-Wall", "-Wextra", "-Werror",
             "-fno-pie", "-no-pie", ROOT / "tests/gcc/varargs-binary64-oracle.c",
             obj, "-o", exe])
        result = run([exe])
        assert result.stdout.startswith("PASS: binary64 va_arg "), result.stdout
        executions.append({"optimization": opt, "stdout": result.stdout,
                           "executable_sha256": sha(exe)})
        print(result.stdout.strip(), opt)
    rejects = {
        "single": (247, "int f(int n,...){va_list a;va_start(a,n);va_arg(a,float);return 0;}"),
        # Long double retrieval and passing are data movement (long-double-check.py);
        # Extended values also support numeric conversions.
    }
    for name, code in {'extended': 'int f(int n,...){va_list a;va_start(a,n);return va_arg(a,long double);}', 'named-extended': 'double f(long double n,...){return n;}', 'variadic-extended-call': 'extern int f(int,...);int g(long double *p){return f(0,(double)*p);}', 'indirect-extended-call': 'int g(int (*f)(int,...),long double *p){return f(0,-*p);}'}.items():
        source = work / (name + ".c")
        source.write_text("#include <stdarg.h>\n" + code + "\n")
        output = work / (name + ".o")
        run([compile, source, output, ROOT / "runtime/gcc-seed/include"])
    for name, (status, code) in rejects.items():
        source = work / (name + ".c")
        source.write_text("#include <stdarg.h>\n" + code + "\n")
        output = work / (name + ".o")
        output.write_bytes(b"previous object\n")
        result = run([compile, source, output, ROOT / "runtime/gcc-seed/include"], status)
        assert not result.stdout and output.read_bytes() == b"previous object\n"
        assert result.stderr.count("error " + str(status)) == 1, result.stderr
        if status == 247:
            assert result.stderr.startswith("varargs: cc: line "), result.stderr
    assert hashes == {str(p.relative_to(ROOT)): sha(p) for p in sources}, "source changed during check"
    report = {"compiler_sha256": hashes, "callee_sha256": sha(obj),
              "host_executions": executions, "checked_rejections": list(rejects),
              "scope": "Incoming binary64 retrieval; shared binary64 argument emission is tested separately"}
    (work / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("PASS: float/long-double retrieval and floating argument boundaries preserve existing outputs")
    print(work / "report.json")


if __name__ == "__main__":
    main()
