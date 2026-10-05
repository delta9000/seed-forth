#!/usr/bin/env python3
"""C90 parameter storage ordering, signature identity and publication safety."""
import argparse
import hashlib
import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--flex-source", type=Path,
                    help="prepared original Flex 2.5.11 source with its measured config.h")
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[2]
(ROOT / "build-out").mkdir(exist_ok=True)
WORK = Path(tempfile.mkdtemp(prefix="parameter-storage-", dir=ROOT / "build-out"))
rows = []


def run(label, command, expected=0):
    p = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=180)
    (WORK / (label + ".stdout")).write_bytes(p.stdout)
    (WORK / (label + ".stderr")).write_bytes(p.stderr)
    rows.append({"name": label, "returncode": p.returncode, "expected": expected})
    (WORK / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
    if p.returncode != expected:
        raise AssertionError((label, p.returncode, expected, p.stderr.decode(errors="replace")))
    return p


production = ROOT / "tests/gcc/parameter-storage.c"
host = ROOT / "tests/gcc/parameter-storage-host.c"
obj = WORK / "production.o"
run("forth-object", [ROOT / "tests/gcc/sysv-object-compile.sh", production, obj])
for opt in ("-O0", "-O2"):
    exe = WORK / ("host" + opt)
    run("host-link" + opt, [os.environ.get("CC", "cc"), "-std=c90", "-pedantic-errors", opt,
                            "-fno-pie", "-no-pie", host, obj, "-o", exe])
    run("host-execute" + opt, [exe])
run("host-source-syntax", [os.environ.get("CC", "cc"), "-std=c90", "-pedantic-errors",
                           "-fsyntax-only", production])
exe = WORK / "all-forth"
run("forth-link", ["python3", ROOT / "tools/gcc-direct-cc.py", production, host, "-o", exe])
run("forth-execute", [exe])

# All C90 declaration-specifier orders must keep unsigned LP64 width.
orders = list(itertools.permutations(("register", "const", "unsigned", "long")))
source = "".join(f"unsigned long order_{i}({' '.join(order)} x){{return x+1;}}\n"
                 for i, order in enumerate(orders))
source += "int main(void){\n" + "".join(
    f"if(order_{i}(0x123456789UL)!=0x12345678aUL)return {i + 1};\n"
    for i in range(len(orders))) + "return 0;}\n"
orders_src = WORK / "specifier-orders.c"
orders_src.write_text(source)
run("specifier-orders-c90", [os.environ.get("CC", "cc"), "-std=c90", "-pedantic-errors",
                             "-fsyntax-only", orders_src])
run("specifier-orders-compile", [ROOT / "tests/gcc/sysv-compile.sh", orders_src,
                                 WORK / "specifier-orders"])
run("specifier-orders-execute", [WORK / "specifier-orders"])

# No function ABI or descriptor weakening is allowed merely by adding register.
rejections = {
    "static": (233, "int f(static const char *);"),
    "extern": (233, "int f(extern const char *);"),
    "auto": (233, "int f(auto const char *);"),
    "typedef": (233, "int f(typedef const char *);"),
    "inline": (233, "int f(inline const char *);"),
    "between-types": (233, "int f(unsigned extern long);"),
    "trailing-storage": (233, "struct S {int n;}; int f(struct S static *);"),
    "nested-storage": (233, "int f(int (*)(register const char *, extern int));"),
    "cast-signature-storage": (233, "int f(void){return sizeof(int (*)(extern int));}"),
    "duplicate-register": (233, "int f(register const register char *);"),
    "register-across-member-context": (233, "int f(register struct {int (*cb)(register const char *);} register *);"),
    "duplicate-after-base": (233, "int f(register int register);"),
    "knr-extern": (233, "int f(x) extern const int x; {return x;}"),
    "knr-auto": (233, "int f(x) const auto int x; {return x;}"),
    "knr-static": (233, "int f(x) int static x; {return x;}"),
    "knr-duplicate": (233, "int f(x) register int register x; {return x;}"),
    "signedness": (237, "int f(register const unsigned char); int f(signed char);"),
    "width": (237, "int f(register const long); int f(int);"),
    "pointer-depth": (237, "int f(register const char **); int f(char *);"),
    "aggregate-identity": (237, "struct A{int x;}; struct B{int x;}; int f(register const struct A *); int f(struct B *);"),
    "callback-identity": (237, "int f(register int (*)(register const char *)); int f(int (*)(int *));"),
    "callback-arity": (237, "int f(register int (*)(register const char *)); int f(int (*)(const char *,int));"),
    "strict-void": (233, "int f(register const void);"),
    "post-pointer-storage": (184, "int f(int * register);"),
}
for label, (code, source) in rejections.items():
    src = WORK / (label + ".c")
    src.write_text(source + "\n")
    out = WORK / (label + ".o")
    previous = b"previous artifact\n"
    out.write_bytes(previous)
    run(label, [ROOT / "tests/gcc/sysv-object-compile.sh", src, out], code)
    assert out.read_bytes() == previous, (label, "overwrote existing artifact")
    out.unlink()
    run(label + "-absent", [ROOT / "tests/gcc/sysv-object-compile.sh", src, out], code)
    assert not out.exists(), (label, "published failed artifact")
if args.flex_source:
    flex = args.flex_source.resolve()
    assert "extern char *copy_string PROTO((register const char *));" in (flex / "flexdef.h").read_text()
    inputs = {name: hashlib.sha256((flex / name).read_bytes()).hexdigest()
              for name in ("ccl.c", "flexdef.h", "config.h")}
    flex_obj = WORK / "original-flex-ccl.o"
    run("original-flex-ccl", ["python3", ROOT / "tools/gcc-direct-cc.py",
                              '-DVERSION="2.5.11"', "-I", flex, "-c",
                              flex / "ccl.c", "-o", flex_obj])
    assert inputs == {name: hashlib.sha256((flex / name).read_bytes()).hexdigest()
                      for name in inputs}, "original source changed"
    (WORK / "original-flex.json").write_text(json.dumps({
        "input_sha256": inputs, "object_sha256": hashlib.sha256(flex_obj.read_bytes()).hexdigest(),
        "object_bytes": flex_obj.stat().st_size, "source_rewritten": False,
    }, indent=2) + "\n")
    print("PASS: untouched original Flex ccl.c with original registered prototype")
print("PASS: parameter specifiers, nested signatures, K&R, host O0/O2, all-Forth execution")
print(f"PASS: {len(rejections)} rejection cases preserve existing/absent outputs")
print(WORK / "results.json")
