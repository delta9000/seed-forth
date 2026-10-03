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
        run([CC, "-c", "entire-program.a"], work, False)
        before = (work / "entire-program.a").read_bytes()
        run([CC, "entire-program.a", "-o", "entire-program.a"], work, False)
        assert (work / "entire-program.a").read_bytes() == before
        (work / "broken.a").write_bytes(b"not an archive")
        (work / "preserved").write_bytes(b"existing output")
        run([CC, "main.o", "broken.a", "-o", "preserved"], work, False)
        assert (work / "preserved").read_bytes() == b"existing output"
        print("PASS: Forth .a driver selection, dependency rescans, unused-member isolation,")
        print("      archive ordering, archive-only main, malformed rejection and atomic aliases")


if __name__ == "__main__":
    main()
