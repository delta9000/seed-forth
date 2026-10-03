#!/usr/bin/env python3
"""Check target-owned macros and an unchanged original GCC ANSI header."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def compile_run(work, name, text, compiler, includes=()):
    source, program = work / (name + ".c"), work / name
    source.write_text(text)
    subprocess.run(["bash", str(ROOT / compiler), str(source), str(program),
                    *map(str, includes)], check=True)
    subprocess.run([str(program)], check=True)
    print("PASS:", name)


def main():
    (ROOT / "build-out").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="target-macros.", dir=ROOT / "build-out") as t:
        work = Path(t)
        compile_run(work, "target-facts", """
#if defined(__GNUC__) || defined(__STDC_VERSION__) || defined(__cplusplus)
int main(void) { return 91; }
#else
int main(void) {
  if (__STDC__ != 1 || __STDC_HOSTED__ != 0 || __SEED_FORTH__ != 1) return 1;
  if (__linux__ != 1 || __x86_64__ != 1 || __LP64__ != 1) return 2;
  if (sizeof(int) != 4 || sizeof(long) != 8 || sizeof(void *) != 8) return 3;
  return 0;
}
#endif
""", "tests/gcc/sysv-compile.sh")
        compile_run(work, "native-macros-unchanged", """
#if defined(__STDC__) || defined(__STDC_HOSTED__) || defined(__SEED_FORTH__)
int main(void) { return 92; }
#else
int main(void) { return 0; }
#endif
""", "tests/tcc/compile-native.sh")
        include = ROOT / "build-out/direct-gcc-inputs/gcc-source/include"
        header = include / "ansidecl.h"
        if not header.is_file():
            print("SKIP: original GCC ansidecl.h is not prepared")
            return
        expected = "8d761202d371342ceff509b7a07cdbbf0ae767c03e3bd9abe57f35b9b15e6a73"
        if hashlib.sha256(header.read_bytes()).hexdigest() != expected:
            raise SystemExit("FAIL: ansidecl.h differs from pinned GCC4.0.4 source")
        compile_run(work, "original-gcc-ansi-header", """
#include "ansidecl.h"
PTR identity PARAMS ((PTR pointer));
PTR identity(PTR pointer) { return pointer; }
int main(void) {
  int value = 19;
  PTR pointer = &value;
  if (sizeof(PTR) != 8) return 1;
  if (identity(pointer) != &value) return 2;
  return 0;
}
""", "tests/gcc/sysv-compile.sh", [include])
        assert hashlib.sha256(header.read_bytes()).hexdigest() == expected


if __name__ == "__main__":
    main()
