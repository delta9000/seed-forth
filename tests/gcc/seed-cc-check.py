#!/usr/bin/env python3
"""seed-cc/seed-ar: Python-free bootstrap, self-rebuild and byte equivalence.

In an isolated source-copy fixture this check

1. runs `./seed-forth < tools/seed-cc-start.fth`, under strace when it is
   available, and requires every execve to be ./seed-forth (no Python,
   shell or other host program runs during the bootstrap);
2. requires the bootstrap's seed-cc and seed-ar to equal the bytes the
   Python driver builds from the same sources, and seed-cc to rebuild
   itself and seed-ar to those same bytes;
3. runs a corpus of commands once with tools/gcc-direct-cc.py and
   tools/gcc-direct-ar.py and once with seed-cc and seed-ar, each time in
   the same freshly created directory, and requires identical exit status,
   stdout, stderr and resulting directory tree (names, modes and bytes).

The corpus covers the driver/archive/library-search test programs, -E
output, stdin, -lm, every rejection message, and (with --all-programs) a
-c and link of every tests/gcc/*.c file.  Host compilers are not used.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ("tools/gcc-direct-cc.py", "tools/gcc-direct-ar.py", "tools/seed-cc.c",
         "tools/seed-ar.c", "tools/seed-tool.h", "tools/seed-cc-start.fth")


def fixture_inputs():
    names = ["000-seed.hex0", "seed-forth", "010-lib.fth", "141-archive.fth", *TOOLS]
    names += [p.name for p in ROOT.glob("[0-9][0-9][0-9]-cc-*.fth")]
    names += [str(p.relative_to(ROOT)) for p in (ROOT / "tools/seed-cc-boot").glob("*.fth")]
    names += [str(p.relative_to(ROOT)) for p in (ROOT / "runtime/gcc-seed").rglob("*")
              if p.is_file() and p.suffix in (".c", ".h")]
    return sorted(set(names))


def make_fixture(fixture):
    names = fixture_inputs()
    data = {name: (ROOT / name).read_bytes() for name in names}
    assert all((ROOT / name).read_bytes() == data[name] for name in names), "source changed during capture"
    for name in names:
        target = fixture / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data[name])
        target.chmod((ROOT / name).stat().st_mode & 0o777)


def bootstrap(fixture, log_dir):
    """Run the Python-free bootstrap; return the number of seed executions."""
    sources = [p for p in (fixture / "runtime/gcc-seed").glob("*.c") if p.name != "math.c"]
    expected = 1 + len(sources) + 2 + 1 + 1 + 2   # loader, units, tools, sysrt, ar, links
    start = (fixture / "tools/seed-cc-start.fth").open("rb")
    command = ["./seed-forth"]
    trace = log_dir / "seed-cc-bootstrap.strace"
    traced = shutil.which("strace") is not None
    if traced:
        probe = subprocess.run(["strace", "-qq", "-f", "--seccomp-bpf", "-e", "trace=execve",
                                "-o", os.devnull, "true"], capture_output=True)
        traced = probe.returncode == 0
    if traced:
        command = ["strace", "-qq", "-f", "--seccomp-bpf", "-e", "trace=execve",
                   "-o", str(trace)] + command
    result = subprocess.run(command, cwd=fixture, stdin=start, capture_output=True, timeout=3600)
    start.close()
    assert (result.returncode, result.stdout, result.stderr) == (0, b"", b""), result
    if not traced:
        print("NOTE: strace unavailable; bootstrap ran without the execve audit")
        return None
    calls = [line for line in trace.read_text().splitlines() if "execve(" in line]
    programs = [re.search(r'execve\("([^"]*)"', line).group(1) for line in calls]
    assert all(line.rstrip().endswith("= 0") for line in calls), calls
    assert set(programs) == {"./seed-forth"}, sorted(set(programs))
    assert len(programs) == expected, (len(programs), expected)
    return len(programs)


def run(command, cwd, data=None):
    try:
        result = subprocess.run([str(part) for part in command], cwd=cwd, input=data,
                                capture_output=True, timeout=600)
    except OSError as error:
        return "not executed", error.errno, b""
    return result.returncode, result.stdout, result.stderr


def tree(directory):
    state = {}
    for path in sorted(directory.rglob("*")):
        name = str(path.relative_to(directory))
        mode = path.lstat().st_mode
        state[name] = (mode, path.read_bytes() if path.is_file() and not path.is_symlink() else None)
    return state


class Drivers:
    def __init__(self, fixture):
        self.python = {"CC": [sys.executable, fixture / "tools/gcc-direct-cc.py"],
                       "AR": [sys.executable, fixture / "tools/gcc-direct-ar.py"]}
        self.native = {"CC": [fixture / "build-out/seed-cc/seed-cc"],
                       "AR": [fixture / "build-out/seed-cc/seed-ar"]}


def replay(work, tools, files, steps):
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    for name, text in files.items():
        path = work / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode() if isinstance(text, str) else text)
    record = []
    for step in steps:
        command, data = (step[0], step[1]) if isinstance(step, tuple) else (step, None)
        command = [part.replace("{W}", str(work)) if isinstance(part, str) else part for part in command]
        if command[0] in tools:
            command = tools[command[0]] + command[1:]
        elif command[0] == "RUN":
            command = [work / command[1]] + command[2:]
        record.append(run(command, work, data))
    return record, tree(work)


def equivalent(base, drivers, case):
    name, files, steps = case
    work = base / name
    python = replay(work, drivers.python, files, steps)
    native = replay(work, drivers.native, files, steps)
    if python == native:
        return name, None, sum(1 for code in python[0] if code[0] == 0)
    why = [f"step {index} {steps[index]}: python {left!r} native {right!r}"
           for index, (left, right) in enumerate(zip(python[0], native[0])) if left != right]
    left, right = python[1], native[1]
    differing = sorted(k for k in set(left) | set(right) if left.get(k) != right.get(k))
    return name, "; ".join(why + [f"trees differ: {differing}"]), 0


PROBE = '''#include "local.h"
#include <choice.h>
#include <stdio.h>
#ifdef __GNUC__
#error driver claimed GNU identity
#endif
#ifdef ERASED
#error undef option failed
#endif
int main(void) {
  if (LOCAL + CHOICE + VALUE + FN(3) != 27) return 1;
  puts("driver production");
  return 0;
}
'''
PROBE_ARGS = ["-Iinclude dir", "-Isecond", "-DVALUE=99", "-UVALUE", "-D", "VALUE=9",
              "-DERASED", "-U", "ERASED", "-DFN(x)=((x)+3)", "source dir/probe.c"]
LIB_SOURCES = {
    "main.c": "int foo(void); int main(void) { return foo() != EXPECT; }\n",
    "foo.c": "int helper(void); int foo(void) { return helper(); }\n",
    "helper.c": "int helper(void) { return 7; }\n",
    "other.c": "int foo(void) { return 9; }\n",
    "poison.c": "int absent(void); int poison(void) { return absent(); }\n",
    "math.c": "#include <math.h>\nint main(void) { return log(1.0) != 0.0 || exp(0.0) != 1.0; }\n",
    "custom-math.c": "double log(double x) { return 17.0; }\n",
    "custom-main.c": "#include <math.h>\nint main(void) { return log(1.0) != 17.0; }\n",
    "first dir/.keep": "", "second/.keep": "", "empty/.keep": "",
}


def corpus(all_programs):
    cases = []
    probe_files = {"source dir/local.h": "#define LOCAL 5\n", "include dir/choice.h": "#define CHOICE 7\n",
                   "second/choice.h": "#error include order changed\n", "source dir/probe.c": PROBE}
    cases.append(("probe", probe_files, [
        ["CC", *PROBE_ARGS, "-o", "program"], ["RUN", "program"],
        ["CC", "-c", *PROBE_ARGS, "-o", "object with spaces.o"],
        ["CC", "object with spaces.o", "-o", "from-object"], ["RUN", "from-object"],
        ["CC", "-E", *PROBE_ARGS], ["CC", "-E", *PROBE_ARGS, "-o", "preprocessed.i"],
        ["CC", "-E", *PROBE_ARGS, "-o", "-"],
        ["CC", "-c", "-static", "-O0", "-g0", "source dir/probe.c", "-Iinclude dir", "-DVALUE=9",
         "-DFN(x)=((x)+3)"],
        (["CC", "-Dmalloc=renamed", "-x", "c", "-", "-o", "isolated"], b"int main(void) { return 0; }\n"),
        ["RUN", "isolated"],
        (["CC", "-E", "-nostdinc", "-"], b"#include <stdio.h>\n"),
        (["CC", "-E", "-nostdinc", "-U__STDC__", "-"], b"#ifdef __STDC__\n#error x\n#endif\nint ok;\n"),
        (["CC", "-E", "-DOPTION=1", "-"], b'__FILE__ __LINE__ OPTION\n'),
        (["CC", "-x", "c", "-c", "-", "-o", "stdin.o"], b"int f(void) { return 3; }\n"),
        ["CC", "-v"], ["CC", "--version"], ["CC", "-dumpmachine"],
        ["CC", "-v", "-c", "source dir/probe.c", "-Iinclude dir", "-DVALUE=9", "-DFN(x)=x+3"],
    ]))
    cases.append(("multi", {
        "a.c": '#include <stdio.h>\nint b(void);\nint main(void) { printf("%d\\n", b()); return 0; }\n',
        "b.c": "int b(void) { return 41 + 1; }\n",
        "c.c": "int c(void) { return 1; }\n"}, [
        ["CC", "-c", "a.c", "b.c", "c.c"], ["CC", "a.o", "b.o", "-o", "linked"], ["RUN", "linked"],
        ["CC", "a.c", "b.c", "-o", "both"], ["RUN", "both"], ["CC", "a.c", "b.o"], ["RUN", "a.out"],
        ["CC", "-E", "a.c", "b.c"],
        ["CC", "--", "a.c", "b.c", "-o"], ["CC", "-c", "--", "c.c"],
    ]))
    steps = [["CC", "-c", "-DEXPECT=7", name] for name in LIB_SOURCES if name.endswith(".c")]
    steps += [
        ["AR", "rcs", "first dir/libfoo.a", "helper.o", "poison.o", "foo.o"],
        ["AR", "rcs", "second/libfoo.a", "other.o"],
        ["AR", "s", "second/libfoo.a"], ["AR", "sD", "first dir/libfoo.a"],
        ["AR", "-rcsD", "libplain.a", "helper.o"], ["AR", "cru", "libcru.a", "helper.o", "foo.o"],
        ["AR", "rc", "libnoindex.a", "foo.o"], ["AR", "s", "libnoindex.a"],
        ["CC", "-Lfirst dir", "-Lsecond", "main.o", "-lfoo", "-o", "p1"], ["RUN", "p1"],
        ["CC", "-L", "first dir", "-L", "second", "main.o", "-l", "foo", "-o", "p2"], ["RUN", "p2"],
        ["CC", "main.o", "-lfoo", "-Lfirst dir", "-Lsecond", "-o", "p3"],
        ["CC", "-c", "-DEXPECT=9", "main.c", "-o", "nine.o"],
        ["CC", "-Lsecond", "-Lfirst dir", "nine.o", "-lfoo", "-o", "p4"], ["RUN", "p4"],
        ["CC", "-Lfirst dir", "-lfoo", "main.o", "-o", "p5"],
        ["CC", "-Lfirst dir", "-lfoo", "main.o", "-lfoo", "-o", "p6"],
        ["CC", "main.o", "-lmissing", "-o", "p7"], ["CC", "main.o", "-Lempty", "-Lsecond", "-lmissing"],
        ["CC", "main.o", "-lc"], ["CC", "main.o", "-Lempty", "-lc"],
        ["CC", "-Lmissing-dir", "main.c", "-DEXPECT=7", "first dir/libfoo.a", "-o", "p8"], ["RUN", "p8"],
        ["CC", "-Lempty", "math.o", "-lm", "-o", "m1"], ["RUN", "m1"],
        ["CC", "-Lempty", "math.o", "-l", "m", "-o", "m2"],
        ["AR", "rcs", "first dir/libm.a", "custom-math.o"],
        ["CC", "-Lfirst dir", "custom-main.o", "-l", "m", "-o", "m3"], ["RUN", "m3"],
        ["CC", "-Lfirst dir", "math.o", "-lm", "-o", "m4"],
        ["CC", "-lmissing", "-L", "missing-dir", "-lm", "-c", "-DEXPECT=7", "main.c", "-l", "c", "-o", "mo.o"],
        ["CC", "-lmissing", "-E", "-DEXPECT=7", "main.c", "-o", "mo.i"],
        ["CC", "foo.o", "helper.o", "-nostdlib", "-o", "nostd"],
        ["CC", "libcru.a", "main.o", "-o", "wrong-order"],
        ["AR", "rcs", "entire.a", "helper.o", "foo.o", "main.o", "poison.o"],
        ["CC", "entire.a", "-o", "all-archive"], ["RUN", "all-archive"],
        ["CC", "main.o", "helper.o", "helper.o", "foo.o", "-o", "duplicate"],
        ["CC", "-c", "entire.a"], ["CC", "entire.a", "-o", "entire.a"],
    ]
    cases.append(("libraries", LIB_SOURCES, steps))
    cases.append(("errors", {"ok.c": "int main(void) { return 0; }\n",
                             "bad.c": "int main(void) { return 0 +; }\n",
                             "undef.c": "int missing(void);\nint main(void) { return missing(); }\n",
                             "broken.a": "not an archive", "preserved": "existing output",
                             "notes.txt": "text\n", "dir/.keep": ""}, [
        ["CC"], ["CC", "-c", "-E", "ok.c"], ["CC", "-O2", "ok.c"], ["CC", "-g", "ok.c"],
        ["CC", "-Wall", "ok.c"], ["CC", "-x", "fortran", "ok.c"], ["CC", "-x"], ["CC", "-o"],
        ["CC", "-I-", "ok.c"], ["CC", "-U", "A=1", "ok.c"], ["CC", "-D", "1bad", "ok.c"],
        ["CC", "-DA\nB", "ok.c"], ["CC", "-o", "a", "-o", "b", "ok.c"], ["CC", "--version", "-dumpmachine"],
        ["CC", "--version", "ok.c"], ["CC", "-c", "ok.c", "bad.c", "-o", "x.o"],
        ["CC", "ok.c", "-o", "-"], ["CC", "notes.txt"], ["CC", "-c", "ok.o"], ["CC", "-"],
        (["CC", "-x", "c", "-", "-x", "c", "-"], b""), ["CC", "missing.c"],
        ["CC", "bad.c", "-o", "preserved"], ["CC", "undef.c", "-o", "preserved"],
        ["CC", "-c", "bad.c"], ["CC", "-E", "bad.c"],
        ["CC", "ok.c", "-o", "ok.c"], ["CC", "ok.c", "-o", "missing-dir/x"], ["CC", "ok.c", "-o", "dir"],
        ["CC", "-c", "ok.c", "dir/../ok.c"], ["CC", "ok.c", "broken.a", "-o", "preserved"],
        ["CC", "-L"], ["CC", "ok.c", "-l"],
        ["AR"], ["AR", "rc"], ["AR", "x", "a.a"], ["AR", "rcc", "a.a"], ["AR", "uc", "u.a", "ok.c"],
        ["AR", "s", "a.a", "ok.c"], ["AR", "cs", "a.a"], ["AR", "rcs", "new.a", "missing.o"],
        ["AR", "s", "broken.a"], ["AR", "--version"], ["AR", "rcs", "new.a", "ok.c"],
    ]))
    # __FILE__ as spelled: main file, quoted header beside it, angle header
    # through -I, and assert() objects, for several source and -I spellings.
    spelling = {"sub/a.c": '#include <assert.h>\n#include "q.h"\n#include <x.h>\n'
                           'const char *main_file = __FILE__;\n'
                           'int f(int v) { assert(v != 3); return v + Q + X; }\n'
                           'int main(void) { return f(1) != 3; }\n',
                "sub/q.h": "#define Q 1\nconst char *quoted_file = __FILE__;\n",
                "inc/x.h": "#define X 1\nconst char *angle_file = __FILE__;\n"}
    steps = []
    for source in ("sub/a.c", "./sub/a.c", "sub//a.c", "sub/../sub/a.c", "{W}/sub/a.c"):
        for include in (["-Iinc"], ["-Iinc/"], ["-I./inc"], ["-Iinc//"], ["-I", "inc"], ["-I{W}/inc"]):
            steps.append(["CC", "-E", *include, source])
        steps.append(["CC", "-c", "-Iinc", source, "-o", "spelled.o"])
        steps.append(["CC", "-I./inc", source, "-o", "spelled"])
        steps.append(["RUN", "spelled"])
    steps += [["CC", "-c", "-Iinc", "-Isub", "sub/a.c", "-o", "two.o"],
              ["CC", "-E", "-I" + "i" * 254, "sub/a.c"], ["CC", "-E", "-Iinc", "s" * 255 + ".c"]]
    cases.append(("file-spelling", spelling, steps))
    # -Werror=implicit-function-declaration on and off.
    implicit = {"undeclared.c": "#include <stdio.h>\nint main(void) {\n  puts(\"x\");\n"
                                "  return later(2);\n}\nint later(int v) { return v - 2; }\n",
                "inc/h.h": "static int from_header(void) { return absent_fn(); }\n",
                "header.c": "#include <h.h>\nint main(void) { return 0; }\n",
                "declared.c": "#include <stdio.h>\n#include <stdarg.h>\n"
                              "static int sum(int n, ...) { va_list a; int t = 0; va_start(a, n);\n"
                              "  while (n--) t += va_arg(a, int); va_end(a); return t; }\n"
                              "int main(void) { extern int puts(const char *); puts(\"ok\");\n"
                              "  return sum(2, 1, 2) != 3; }\n",
                "lined.c": "#line 40 \"renamed.c\"\nint main(void) { return gone(); }\n"}
    flag = "-Werror=implicit-function-declaration"
    cases.append(("implicit-error", implicit, [
        ["CC", "-c", "undeclared.c"], ["CC", "-c", flag, "undeclared.c", "-o", "flagged.o"],
        ["CC", flag, "undeclared.c", "-o", "flagged"], ["CC", "undeclared.c", "-o", "plain"], ["RUN", "plain"],
        ["CC", "-c", flag, "-Iinc", "header.c"], ["CC", "-c", flag, "lined.c"],
        ["CC", "-c", flag, "./undeclared.c", "-o", "dot.o"],
        ["CC", "-c", flag, "declared.c", "-o", "declared-flag.o"], ["CC", "-c", "declared.c"],
        ["CC", flag, "declared.c", "-o", "declared"], ["RUN", "declared"],
        ["CC", "-E", flag, "declared.c", "-o", "declared.i"],
        (["CC", "-x", "c", flag, "-c", "-", "-o", "stdin.o"], b"int main(void) { return nope(); }\n"),
        ["CC", "-Werror=implicit", "declared.c"], ["CC", "-Werror", "declared.c"],
    ]))
    cases.append(("long-paths", {"ok.c": "int main(void) { return 0; }\n"}, [
        ["CC", "-I" + "d" * 260, "ok.c"], ["CC", "-c", "x" * 252 + ".c"],
    ]))
    tests = sorted((ROOT / "tests/gcc").glob("*.c"))
    if not all_programs:
        wanted = {"driver-runtime-check.c", "stdio-check.c", "abs.c", "getopt-check.c",
                  "atol-check.c", "bufsiz-check.c", "strcspn-check.c"}
        tests = [p for p in tests if p.name in wanted]
    for source in tests:
        stem = source.stem
        steps = [["CC", "-c", "-I", str(source.parent), str(source), "-o", stem + ".o"],
                 ["CC", "-E", "-I", str(source.parent), str(source), "-o", stem + ".i"]]
        if b"main" in source.read_bytes():
            steps.append(["CC", "-I", str(source.parent), str(source), "-o", stem])
        cases.append(("program-" + stem, {}, steps))
    return cases


def extensions(base, drivers):
    """seed-ar's GNU-style r/u on existing archives, which the Python adapter
    refuses: every result must equal the Python adapter's fresh archive of the
    resulting member list."""
    work = base / "ar-update"
    work.mkdir(parents=True)
    sources = {"helper": "int helper(void) { return 7; }\n",
               "poison": "int absent(void); int poison(void) { return absent(); }\n",
               "foo": "int helper(void); int foo(void) { return helper(); }\n",
               "other": "int poison(void) { return 9; }\n"}
    cc, ar, py_ar = drivers.native["CC"], drivers.native["AR"], drivers.python["AR"]
    for name, text in sources.items():
        (work / (name + ".c")).write_text(text)
        assert run([*cc, "-c", name + ".c"], work) == (0, b"", b"")
    (work / "new").mkdir()
    (work / "new/poison.o").write_bytes((work / "other.o").read_bytes())

    def fresh(*members):
        out = work / "expected.a"
        out.unlink(missing_ok=True)
        assert run([*py_ar, "rcs", out, *members], work) == (0, b"", b"")
        return out.read_bytes()

    assert run([*ar, "r", "created.a", "helper.o"], work) == (0, b"", b"gcc-direct-ar: creating created.a\n")
    assert (work / "created.a").read_bytes() == fresh("helper.o")
    assert run([*ar, "rcs", "lib.a", "helper.o", "poison.o"], work) == (0, b"", b"")
    assert run([*ar, "rcs", "lib.a", "foo.o"], work) == (0, b"", b"")
    assert (work / "lib.a").read_bytes() == fresh("helper.o", "poison.o", "foo.o")
    assert run([*ar, "ru", "lib.a", "new/poison.o"], work) == (0, b"", b"")
    assert (work / "lib.a").read_bytes() == fresh("helper.o", "new/poison.o", "foo.o")
    assert run([*ar, "cru", "lib.a", "poison.o", "helper.o"], work) == (0, b"", b"")
    assert (work / "lib.a").read_bytes() == fresh("helper.o", "poison.o", "foo.o")
    (work / "text").write_bytes(b"not an archive")
    code = run([*ar, "rcs", "text", "foo.o"], work)
    assert code[0] == 2 and b"is not a GNU ar archive" in code[2], code
    assert (work / "text").read_bytes() == b"not an archive"
    return 5


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--all-programs", action="store_true",
                        help="also compile and link every tests/gcc/*.c with both drivers")
    parser.add_argument("--jobs", type=int, default=4)
    options = parser.parse_args()
    (ROOT / "build-out").mkdir(exist_ok=True)
    fixture = Path(tempfile.mkdtemp(prefix="seed-cc-check-", dir=ROOT / "build-out"))
    try:
        make_fixture(fixture)
        executions = bootstrap(fixture, fixture)
        out = fixture / "build-out/seed-cc"
        boot = {name: (out / name).read_bytes() for name in ("seed-cc", "seed-ar")}
        rebuilt = fixture / "build-out/rebuilt"
        rebuilt.mkdir()
        for tool in ("seed-cc", "seed-ar"):
            source = f"tools/{tool}.c"
            code = run([sys.executable, fixture / "tools/gcc-direct-cc.py", source,
                        "-o", rebuilt / (tool + ".python")], fixture)
            assert code == (0, b"", b""), code
            code = run([out / "seed-cc", source, "-o", rebuilt / (tool + ".native")], fixture)
            assert code == (0, b"", b""), code
            assert (rebuilt / (tool + ".python")).read_bytes() == boot[tool], tool + " differs from Python build"
            assert (rebuilt / (tool + ".native")).read_bytes() == boot[tool], tool + " differs from self-rebuild"
        code = run([rebuilt / "seed-cc.native", "tools/seed-cc.c", "-o", rebuilt / "seed-cc.second"], fixture)
        assert code == (0, b"", b"") and (rebuilt / "seed-cc.second").read_bytes() == boot["seed-cc"]
        drivers = Drivers(fixture)
        cases = corpus(options.all_programs)
        base = fixture / "eq"
        with ThreadPoolExecutor(max_workers=options.jobs) as executor:
            results = list(executor.map(lambda case: equivalent(base, drivers, case), cases))
        failures = [(name, why) for name, why, _ in results if why]
        succeeded = sum(count for _, _, count in results)
        for name, why in failures:
            print(f"DIFFERENT: {name}: {why}"[:4000])
        commands = sum(len(steps) for _, _, steps in cases)
        if failures:
            raise SystemExit(f"FAIL: {len(failures)} of {len(cases)} seed-cc equivalence cases differ")
        updates = extensions(base, drivers)
        audit = f"{executions} execve calls, all ./seed-forth" if executions else "no execve audit"
        print(f"PASS: Python-free seed-cc/seed-ar bootstrap ({audit}); bootstrap = Python build")
        print(f"      = self-rebuild; {len(cases)} cases, {commands} commands ({succeeded} succeeding)")
        print("      byte-identical to the Python driver;")
        print(f"      {updates} seed-ar archive updates equal fresh Python-adapter archives")
    finally:
        shutil.rmtree(fixture, ignore_errors=True)


if __name__ == "__main__":
    main()
