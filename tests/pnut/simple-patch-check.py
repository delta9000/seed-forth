#!/usr/bin/env python3
"""Normal CLI reliability checks; accepts the chain-built helper as argv[1]."""
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import tempfile

helper = str(Path(sys.argv[1]).resolve())
count = 0

def limited_output():
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    resource.setrlimit(resource.RLIMIT_FSIZE, (8, 8))

with tempfile.TemporaryDirectory(prefix="simple-patch-check-") as directory:
    root = Path(directory)
    def check(name, data=b"alpha old omega\n", before=b"old", after=b"NEW", *,
              success=True, expected=None, copy=False, missing=False,
              existing=False, directory_input=False, limit=False, mode=None):
        global count
        work = root / name
        work.mkdir()
        source, old, new, output = [work / f for f in ("input", "before", "after", "output")]
        if directory_input:
            source.mkdir()
        elif not missing:
            source.write_bytes(data)
        old.write_bytes(before)
        new.write_bytes(after)
        if existing:
            output.write_bytes(b"must remain unchanged")
        args = [helper, "copy", str(source), str(output)] if copy else [helper, "replace", str(source), str(old), str(new), str(output)]
        env = dict(os.environ)
        if mode:
            env["SIMPLE_PATCH_TEST_IO"] = mode
        run = subprocess.run(args, capture_output=True, env=env,
                             preexec_fn=limited_output if limit else None)
        assert (run.returncode == 0) == success, (name, run.returncode, run.stderr)
        if success:
            want = expected if expected is not None else data if copy else data.replace(before, after, 1)
            assert output.read_bytes() == want, name
        elif existing:
            assert output.read_bytes() == b"must remain unchanged", name
        else:
            assert not output.exists(), (name, "partial output remained")
        if not missing and not directory_input:
            assert source.read_bytes() == data, (name, "input changed")
        count += 1
        print("PASS:", name)

    check("unique")
    check("match-at-start", data=b"old tail")
    check("match-at-end", data=b"head old")
    check("whole-file", data=b"old")
    check("delete", after=b"")
    check("binary", data=b"\x00old\x00", before=b"old\x00", after=b"\xff\x00")
    check("empty-before", before=b"", success=False)
    check("no-match", before=b"missing", success=False)
    check("duplicate", data=b"old old", success=False)
    check("overlapping-duplicate", data=b"aaa", before=b"aa", success=False)
    check("empty-input", data=b"", success=False)
    check("pattern-longer", data=b"o", success=False)
    check("missing-input", missing=True, success=False)
    check("directory-input", directory_input=True, success=False)
    check("existing-output", existing=True, success=False)
    check("copy", copy=True)
    check("copy-empty", data=b"", copy=True)
    check("copy-existing-output", copy=True, existing=True, success=False)
    check("write-limit", data=b"x" * 4096, copy=True, limit=True, success=False)
    if len(sys.argv) > 2 and sys.argv[2] == "--injected-io":
        check("short-reads-writes", mode="short")
        check("read-error", mode="read-error", success=False)
        check("zero-write", mode="zero-write", success=False)
        check("close-error", mode="close-error", success=False)
    # Output alias checks: O_EXCL must reject existing symlinks/hardlinks too.
    for alias in ("symlink", "hardlink", "same-path"):
        work = root / alias
        work.mkdir()
        source = work / "input"
        source.write_bytes(b"unchanged")
        output = source if alias == "same-path" else work / "output"
        if alias == "symlink":
            output.symlink_to(source)
        if alias == "hardlink":
            os.link(source, output)
        run = subprocess.run([helper, "copy", str(source), str(output)], capture_output=True)
        assert run.returncode != 0 and source.read_bytes() == b"unchanged", alias
        count += 1
        print("PASS:", alias)
print(f"PASS: {count} simple-patch checks")
