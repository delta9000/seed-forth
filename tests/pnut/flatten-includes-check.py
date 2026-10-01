#!/usr/bin/env python3
"""Byte equality with the pinned flattener plus bounded failure checks.

Usage: python3 tests/pnut/flatten-includes-check.py PATH_TO_FLATTENER
The shell/Python oracle is test-only; neither runs on the bootstrap path.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HELPER = str(Path(sys.argv[1]).resolve())
ORACLE = ROOT / "vendor/pnut/utils/process-includes.sh"
ENV = dict(os.environ, LC_ALL="C")
passed = 0


def passed_check(name):
    global passed
    passed += 1
    print("PASS:", name)


kit_input = ROOT / "vendor/pnut/kit/bintools/bintools-base.c"
actual = subprocess.run([HELPER, str(kit_input)], capture_output=True, env=ENV, check=True)
expected = subprocess.run([str(ORACLE), str(kit_input)], capture_output=True, env=ENV, check=True)
assert actual.stdout == expected.stdout
assert hashlib.sha256(actual.stdout).hexdigest() == "d7dbb22dfb0ab6b689c33a55b23b2f9baabd7eb3df653627fd5b3c89276e4102"
passed_check("pinned bintools.c equals shell oracle (68580 bytes)")

with tempfile.TemporaryDirectory(prefix="flatten-includes-check-") as directory:
    base = Path(directory)

    def check(name, files, *, success=True, want=None, oracle=True):
        work = base / name
        work.mkdir()
        for filename, data in files.items():
            (work / filename).write_bytes(data)
        run = subprocess.run([HELPER, "input.c"], cwd=work, capture_output=True, env=ENV)
        assert (run.returncode == 0) == success, (name, run.returncode, run.stderr)
        if success:
            if oracle:
                ref = subprocess.run([str(ORACLE), "input.c"], cwd=work, capture_output=True, env=ENV, check=True)
                assert run.stdout == ref.stdout, (name, run.stdout, ref.stdout)
            if want is not None:
                assert run.stdout == want, (name, run.stdout, want)
        else:
            assert run.stdout == b"", (name, "partial source emitted on input failure")
        passed_check(name)

    check("empty", {"input.c": b""}, want=b"")
    check("ordinary-lines", {"input.c": b"a\n\nb\n"})
    check("system-dedup", {"input.c": b"#include <stdio.h>\n#include <stdio.h>\n"})
    check("header-substring", {"input.c": b"#include <sys/stat.h>\n#include <stat.h>\n"})
    check("grep-dot-wildcard", {"input.c": b"#include <axb>\n#include <a.b>\n"})
    check("grep-across-header-boundary", {"input.c": b"#include <xa>\n#include <b>\n#include <a.b>\n"})
    check("repeat-user-include", {"input.c": b'#include "part.c"\n#include "part.c"\n', "part.c": b"part\n"}, want=b"part\npart\n")
    check("nested-and-global-dedup", {"input.c": b'#include <a.h>\n#include "part.c"\n#include <b.h>\n', "part.c": b'#include <b.h>\n#include "last.c"\n', "last.c": b"#include <a.h>\nlast\n"})
    check("conditions-unevaluated", {"input.c": b'#if 0\n#include "part.c"\n#endif\n', "part.c": b"part\n"})
    check("nonmatching-directives-preserved", {"input.c": b' #include "missing.c"\n#include <a.h> // trailing\n#include\t<a.h>\n'})
    check("crlf-preserved", {"input.c": b'#include "missing.c"\r\nordinary\r\n'})
    check("unterminated-root-line-dropped", {"input.c": b"first\nlast"}, want=b"first\n")
    check("unterminated-child-line-dropped", {"input.c": b'#include "part.c"\nlast\n', "part.c": b"omitted"}, want=b"last\n")
    check("missing-input", {}, success=False)
    check("missing-child", {"input.c": b'prefix\n#include "missing.c"\n'}, success=False)
    check("self-cycle", {"input.c": b'#include "input.c"\n'}, success=False)
    check("mutual-cycle", {"input.c": b'#include "part.c"\n', "part.c": b'#include "input.c"\n'}, success=False)
    check("nul-rejected", {"input.c": b"prefix\n\x00\n"}, success=False)
    check("empty-system-name", {"input.c": b"#include <>\n"}, success=False)
    check("empty-quoted-name", {"input.c": b'#include ""\n'}, success=False)
    check("unsupported-system-regex", {"input.c": b"#include <a[bc].h>\n"}, success=False)
    check("quoted-subpath-rejected", {"input.c": b'#include "sub/file.h"\n'}, success=False)
    check("line-limit", {"input.c": b"x" * 65536 + b"\n"}, success=False)
    check("file-limit", {"input.c": b"x" * 1048577}, success=False)
    chain = {"input.c": b'#include "f1.c"\n'}
    for index in range(1, 34):
        chain[f"f{index}.c"] = f'#include "f{index+1}.c"\n'.encode()
    check("depth-limit", chain, success=False)
    check("output-limit", {"input.c": b'#include "part.c"\n' * 5, "part.c": b"x\n" * 524288}, success=False)
    work = base / "directory-input"
    work.mkdir()
    run = subprocess.run([HELPER, str(work)], capture_output=True, env=ENV)
    assert run.returncode != 0 and run.stdout == b""
    passed_check("directory-input")
    with open("/dev/full", "wb", buffering=0) as sink:
        run = subprocess.run([HELPER, str(kit_input)], stdout=sink, stderr=subprocess.PIPE, env=ENV)
    assert run.returncode != 0 and b"output write failed" in run.stderr
    passed_check("output-write-failure")
print(f"PASS: {passed} include-flattener checks")
