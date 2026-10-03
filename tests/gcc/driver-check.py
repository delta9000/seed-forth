#!/usr/bin/env python3
"""Exercise the direct driver using only Forth-generated target artifacts."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "tools/gcc-direct-cc.py"


def run(*arguments, cwd, success=True, data=None):
    result = subprocess.run([DRIVER, *arguments], cwd=cwd, input=data,
                            capture_output=True, timeout=60)
    if (result.returncode == 0) != success:
        raise AssertionError((arguments, result.returncode, result.stdout, result.stderr))
    if success and result.stderr:
        raise AssertionError((arguments, result.stderr))
    return result


def execute(path, expected=b""):
    result = subprocess.run([path], capture_output=True, timeout=10)
    assert (result.returncode, result.stdout, result.stderr) == (0, expected, b""), result


def main():
    with tempfile.TemporaryDirectory(prefix="driver-check-") as directory:
        work = Path(directory)
        (work / "source dir").mkdir()
        (work / "include dir").mkdir()
        (work / "second").mkdir()
        (work / "source dir/local.h").write_text("#define LOCAL 5\n")
        (work / "include dir/choice.h").write_text("#define CHOICE 7\n")
        (work / "second/choice.h").write_text("#error include order changed\n")
        source = work / "source dir/probe.c"
        source.write_text('''#include "local.h"
#include <choice.h>
#include <stdio.h>
#ifdef __GNUC__
#error driver claimed GNU identity
#endif
#ifndef __SEED_FORTH__
#error driver lost seed identity
#endif
#ifdef ERASED
#error undef option failed
#endif
int main(void) {
  if (LOCAL + CHOICE + VALUE + FN(3) != 27) return 1;
  puts("driver production");
  return 0;
}
''')
        args = ("-Iinclude dir", "-Isecond", "-DVALUE=99", "-UVALUE", "-D", "VALUE=9",
                "-DERASED", "-U", "ERASED", "-DFN(x)=((x)+3)", str(source))
        run(*args, "-o", "program", cwd=work)
        execute(work / "program", b"driver production\n")
        run("-c", *args, "-o", "object with spaces.o", cwd=work)
        run("object with spaces.o", "-o", "from-object", cwd=work)
        execute(work / "from-object", b"driver production\n")
        preprocessed = run("-E", *args, cwd=work).stdout
        assert b"#include" not in preprocessed and b"99" not in preprocessed
        assert b"int main" in preprocessed and b"LOCAL" not in preprocessed
        run("-E", *args, "-o", "preprocessed.i", cwd=work)
        assert (work / "preprocessed.i").read_bytes() == preprocessed
        # User macro choices must never leak into building the runtime.
        run("-Dmalloc=renamed_by_user", "-Dprintf=also_renamed", "-x", "c", "-",
            "-o", "isolated", data=b"int main(void) { return 0; }\n", cwd=work)
        execute(work / "isolated")
        run("-E", "-nostdinc", "-", data=b"#include <stdio.h>\n", cwd=work, success=False)
        run("-E", "-nostdinc", "-U__STDC__", "-",
            data=b"#ifdef __STDC__\n#error failed undef\n#endif\nint ok;\n", cwd=work)
        (work / "stdin-header.h").write_text("#define STDIN_VALUE 7\n")
        stdin_pp = run("-E", "-DOPTION=1", "-", cwd=work,
                       data=b'#include "stdin-header.h"\n__FILE__ __LINE__ STDIN_VALUE\n').stdout
        assert stdin_pp.split() == [b'"<stdin>"', b"2", b"7"], stdin_pp
        assert b"seed-forth" in run("--version", cwd=work).stdout
        assert run("-dumpmachine", cwd=work).stdout == b"x86_64-pc-linux-gnu\n"
        identity = run("--print-source-hash", cwd=work).stdout.decode().strip()
        assert len(identity) == 64
        manifest = json.loads((ROOT / "build-out/gcc-direct-cache" / identity / "manifest.json").read_text())
        assert not manifest["host_compiler"] and not manifest["host_linker"]
        for flag in ("-g", "-O2", "-shared", "-fPIC", "-std=c99", "-lfoo", "-I-", "-traditional-cpp"):
            result = run(flag, str(source), cwd=work, success=False)
            assert b"unsupported" in result.stderr
        protected = work / "protected.c"
        protected.write_text("int main(void) { return 0; }\n")
        before = protected.read_bytes()
        for options, output, expected_mode in ((["-c"], "private.o", 0o600),
                                               ([], "private-program", 0o700)):
            result = subprocess.run([DRIVER, *options, "protected.c", "-o", output],
                                    cwd=work, capture_output=True, timeout=60, umask=0o077)
            assert (result.returncode, result.stderr) == (0, b""), result
            assert (work / output).stat().st_mode & 0o777 == expected_mode
        run("-c", "protected.c", "-o", "protected.c", cwd=work, success=False)
        (work / "alias.o").symlink_to(protected)
        run("-c", "protected.c", "-o", "alias.o", cwd=work, success=False)
        (work / "hard.o").hardlink_to(protected)
        run("-c", "protected.c", "-o", "hard.o", cwd=work, success=False)
        assert protected.read_bytes() == before
        (work / "old-output").write_bytes(b"preserve me")
        run("-x", "c", "-", "-o", "old-output", data=b"#error deliberate failure\n", cwd=work, success=False)
        assert (work / "old-output").read_bytes() == b"preserve me"
        # Every source is compiled before any -c result gets published.
        (work / "good.c").write_text("int good(void) { return 0; }\n")
        (work / "bad.c").write_text("#error fail the batch\n")
        run("-c", "good.c", "bad.c", cwd=work, success=False)
        assert not (work / "good.o").exists()
        run("-c", "protected.c", "source dir/probe.c", "-o", "out.o", cwd=work, success=False)
        (work / "second/protected.c").write_bytes(before)
        run("-c", "protected.c", "second/protected.c", cwd=work, success=False)
        run("-x", "c", "-", "-o", "missing/program", data=before, cwd=work, success=False)
        # Parallel compiler invocations share no temporary object/output names.
        def parallel(index):
            run("protected.c", "-o", f"parallel-{index}", cwd=work)
            execute(work / f"parallel-{index}")
        with ThreadPoolExecutor(max_workers=4) as executor:
            list(executor.map(parallel, range(4)))
        print("PASS: direct-driver preprocess, macro/include order, compile/link, runtime isolation,")
        print("      option rejection, atomic outputs, aliases, batch failures and concurrency")


if __name__ == "__main__":
    main()
