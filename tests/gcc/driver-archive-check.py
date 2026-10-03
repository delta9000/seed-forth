#!/usr/bin/env python3
"""Exercise driver .a inputs using only Forth-built objects, ar and linker."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CC = ROOT / "tools/gcc-direct-cc.py"
AR = ROOT / "tools/gcc-direct-ar.py"


def run(command, work, success=True):
    result = subprocess.run(command, cwd=work, capture_output=True, timeout=60)
    assert (result.returncode == 0) == success, (command, result)
    if success:
        assert not result.stdout and not result.stderr, (command, result)
    return result


def main():
    with tempfile.TemporaryDirectory(prefix="driver-archive-") as directory:
        work = Path(directory)
        sources = {"main": "int needed(void); int main(void) { return needed() != 7; }\n",
                   "needed": "int helper(void); int needed(void) { return helper(); }\n",
                   "helper": "int helper(void) { return 7; }\n",
                   "poison": "int absent(void); int poison(void) { return absent(); }\n"}
        for name, text in sources.items():
            (work / (name + ".c")).write_text(text)
            run([CC, "-c", name + ".c"], work)
        # helper precedes its newly discovered reference. The unneeded poison
        # member must not be loaded, as its unresolved reference would fail.
        run([AR, "rcs", "library with spaces.a", "helper.o", "poison.o", "needed.o"], work)
        run([CC, "main.o", "library with spaces.a", "-o", "program"], work)
        run([work / "program"], work)
        run([CC, "main.c", "library with spaces.a", "-o", "from-source"], work)
        run([work / "from-source"], work)
        # Match ordinary static-link ordering: an archive is searched at its
        # position, then internally revisited to resolve newly selected refs.
        run([CC, "library with spaces.a", "main.o", "-o", "wrong-order"], work, False)
        assert not (work / "wrong-order").exists()
        # Default startup must make main undefined before archive selection.
        run([AR, "rcs", "entire-program.a", "helper.o", "needed.o", "main.o", "poison.o"], work)
        run([CC, "entire-program.a", "-o", "all-archive"], work)
        run([work / "all-archive"], work)
        # A source package can provide the complete getopt member itself.
        # The default runtime must not select its competing member merely
        # because the program uses another runtime service such as printf.
        (work / "own-getopt.c").write_text(
            "#include <unistd.h>\n"
            "char *optarg; int optind=1, opterr=1, optopt;\n"
            "int getopt(int n,char *const *v,const char *s) { return 71; }\n")
        (work / "own-main.c").write_text(
            "#include <stdio.h>\n#include <unistd.h>\n"
            "int main(int n,char **v) { int x=getopt(n,v,\"\"); "
            "printf(\"%d\\n\",x); return x!=71; }\n")
        run([CC, "-c", "own-getopt.c"], work)
        run([CC, "-c", "own-main.c"], work)
        run([CC, "own-main.o", "own-getopt.o", "-o", "own-program"], work)
        actual = subprocess.run([work / "own-program"], capture_output=True, timeout=10)
        assert (actual.returncode, actual.stdout, actual.stderr) == (0, b"71\n", b""), actual
        run([AR, "rcs", "own-provider.a", "own-getopt.o"], work)
        run([CC, "own-main.o", "own-provider.a", "-o", "own-archive-program"], work)
        actual = subprocess.run([work / "own-archive-program"], capture_output=True, timeout=10)
        assert (actual.returncode, actual.stdout, actual.stderr) == (0, b"71\n", b""), actual
        # Eager duplicate definitions remain an error, with atomic output.
        (work / "duplicate-output").write_bytes(b"existing output")
        duplicate = run([CC, "own-main.o", "own-getopt.o", "own-getopt.o",
                         "-o", "duplicate-output"], work, False)
        assert duplicate.returncode == 252, duplicate
        assert (work / "duplicate-output").read_bytes() == b"existing output"
        run([CC, "-c", "entire-program.a"], work, False)
        before = (work / "entire-program.a").read_bytes()
        run([CC, "entire-program.a", "-o", "entire-program.a"], work, False)
        assert (work / "entire-program.a").read_bytes() == before
        (work / "broken.a").write_bytes(b"not an archive")
        (work / "preserved").write_bytes(b"existing output")
        run([CC, "main.o", "broken.a", "-o", "preserved"], work, False)
        assert (work / "preserved").read_bytes() == b"existing output"
        print("PASS: Forth .a driver selection, dependency rescans, unused-member isolation,")
        print("      archive ordering, archive-only main, runtime member replacement,")
        print("      eager duplicate rejection, malformed rejection and atomic aliases")


if __name__ == "__main__":
    main()
