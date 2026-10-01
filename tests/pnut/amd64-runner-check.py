#!/usr/bin/env python3
"""Ordinary correctness checks for the seed-built amd64 recipe runner.

Usage: amd64-runner-check.py RUNNER [--simple-patch HELPER]
Host executables below are verification fixtures only, never recipe inputs.
All writes and BUILDROOT cleanup probes stay in disposable temporary trees.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("runner", type=Path)
parser.add_argument("--simple-patch", type=Path,
                    default=ROOT / "build-out/pnut-amd64/kit/simple-patch")
options = parser.parse_args()
RUNNER = str(options.runner.resolve())
HELPER = options.simple_patch.resolve()
SHA = lambda data: hashlib.sha256(data).hexdigest()
passed = []
failed = []


def record(name, action):
    try:
        action()
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        failed.append((name, str(error)))
        print(f"FAIL: {name}: {error}", flush=True)
    else:
        passed.append(name)
        print(f"PASS: {name}", flush=True)


def run_recipe(work, script, success=True):
    recipe = work / "test.recipe"
    recipe.write_text(script)
    run = subprocess.run([RUNNER, "--recipe", str(recipe)], cwd=work,
                         capture_output=True, timeout=30)
    assert (run.returncode == 0) == success, (run.returncode, run.stderr.decode(errors="replace"))
    return run


def snapshot(path):
    result = {}
    for current, directories, files in os.walk(path, followlinks=False):
        for name in directories + files:
            item = Path(current) / name
            relative = str(item.relative_to(path))
            if item.is_symlink():
                result[relative] = ("link", os.readlink(item))
            elif item.is_file():
                result[relative] = ("file", item.read_bytes())
            else:
                result[relative] = ("directory",)
    return result


def launch(work, buildroot, payload):
    payload.write_text(str(buildroot) + "\n")
    try:
        saved = os.dup(9)
    except OSError:
        saved = None
    fd = os.open(payload, os.O_RDONLY)
    try:
        if fd != 9:
            os.dup2(fd, 9)
        try:
            return subprocess.run([RUNNER], cwd=work, pass_fds=(9,),
                                  capture_output=True, timeout=30)
        finally:
            if saved is None:
                os.close(9)
            else:
                os.dup2(saved, 9)
                os.close(saved)
    finally:
        if fd != 9:
            os.close(fd)


with tempfile.TemporaryDirectory(prefix="amd64-runner-check-") as temporary:
    base = Path(temporary)

    def new(name):
        work = base / name
        work.mkdir()
        return work

    for size in (0, 1, 3, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129, 65535, 65536, 65537, 1048593):
        def hash_case(size=size):
            work = new(f"hash-{size}")
            data = b"abc" if size == 3 else bytes((index * 131 + 17) & 255 for index in range(size))
            (work / "input").write_bytes(data)
            run = run_recipe(work, f"hash input\npin input {SHA(data)}\n")
            assert run.stdout == (SHA(data) + "\n").encode(), run.stdout
        record(f"SHA256-{size}", hash_case)

    def binary_files():
        work = new("binary-files")
        a = bytes(range(256)) * 519
        b = b"\x00tail\xff\n"
        (work / "a").write_bytes(a)
        (work / "b").write_bytes(b)
        (work / "empty").write_bytes(b"")
        run_recipe(work, "copy a copied\ncat combined empty a b empty\nsame a copied\n")
        assert (work / "copied").read_bytes() == a
        assert (work / "combined").read_bytes() == a + b
    record("binary-copy-cat-same", binary_files)

    for name, a, b in (("byte-mismatch", b"abc", b"abd"),
                       ("left-shorter", b"abc", b"abcd"),
                       ("right-shorter", b"abcd", b"abc"),
                       ("empty-versus-nonempty", b"", b"x")):
        def comparison(name=name, a=a, b=b):
            work = new(name)
            (work / "a").write_bytes(a)
            (work / "b").write_bytes(b)
            run_recipe(work, "same a b\n", success=False)
            assert (work / "a").read_bytes() == a and (work / "b").read_bytes() == b
        record(name, comparison)

    def quoting():
        work = new("quoting")
        run_recipe(work, 'set V "hello world"\ntext "out file" "${V}\\nline\\tend" # comment\n'
                   'text literal "a#b"\nset V replaced\ntext next \'${V}\'\ntext empty ""\n')
        assert (work / "out file").read_bytes() == b"hello world\nline\tend"
        assert (work / "literal").read_bytes() == b"a#b"
        assert (work / "next").read_bytes() == b"replaced"
        assert (work / "empty").read_bytes() == b""
    record("quotes-escapes-variables-comments", quoting)

    for name, script in {
        "undefined-variable": 'say "${ABSENT}"\n',
        "unclosed-variable": 'say "${ROOT"\n',
        "unterminated-quote": 'say "missing\n',
        "unsupported-escape": 'say "bad\\q"\n',
        "trailing-escape": 'say end\\',
        "wrong-arity": 'copy one\n',
        "unknown-command": 'not-a-command\n',
        "invalid-exit-number": 'run nope - - - /bin/true\n',
        "oversized-exit-number": 'run 256 - - - /bin/true\n',
        "PATH-command-refused": 'run 0 - - - true\n',
        "wrong-child-exit": 'run 0 - - - /bin/false\n',
        "child-signal": "run 0 - - - /bin/sh -c 'kill -TERM $$'\n",
        "missing-child": 'run 0 - - - ./does-not-exist\n',
        "token-limit": 'say "' + 'x' * 16384 + '"\n',
        "argument-limit": 'say ' + 'x ' * 128 + '\n',
        "variable-limit": ''.join(f'set V{i} value\n' for i in range(32)),
    }.items():
        record(name, lambda name=name, script=script: run_recipe(new(name), script, success=False))

    def child_success():
        work = new("child-success")
        (work / "input").write_bytes(b"input\x00bytes\xff")
        run_recipe(work, "run 0 - - - /bin/true\nrun 1 - - - /bin/false\n"
                   "run 0 input output error /bin/cat\n"
                   "run 7 - - - /bin/sh -c 'exit 7'\n")
        assert (work / "output").read_bytes() == (work / "input").read_bytes()
        assert (work / "error").read_bytes() == b""
    record("explicit-child-exits-and-redirection", child_success)

    assert HELPER.is_file(), f"simple-patch fixture missing: {HELPER}"
    for case in ("replace", "copy", "bad-pre", "bad-post", "ambiguous",
                 "stale-candidate", "candidate-symlink", "existing-add", "dangling-add-symlink"):
        def patch_case(case=case):
            work = new("patch-" + case)
            shutil.copy2(HELPER, work / "simple-patch")
            data = work / "data"
            data.mkdir()
            original = b"old old" if case == "ambiguous" else b"an old file"
            changed = b"an new file"
            (data / "before").write_bytes(b"old")
            (data / "after").write_bytes(b"new")
            (data / "added").write_bytes(b"added file")
            target = work / "target"
            candidate = work / "target.sf-patch-new"
            copying = case in ("copy", "existing-add", "dangling-add-symlink")
            if not copying:
                target.write_bytes(original)
            if case == "existing-add":
                target.write_bytes(b"keep")
            if case == "dangling-add-symlink":
                target.symlink_to("absent")
            if case == "stale-candidate":
                candidate.write_bytes(b"keep candidate")
            if case == "candidate-symlink":
                candidate.symlink_to(target)
            pre = SHA(b"added file" if copying else original)
            post = SHA(b"added file" if copying else changed)
            if case == "bad-pre":
                pre = "0" * 64
            if case == "bad-post":
                post = "0" * 64
            operation = f"copy added target - - {pre} {post}" if copying else f"replace target target before after {pre} {post}"
            (work / "manifest").write_text(operation + "\n")
            success = case in ("replace", "copy")
            run_recipe(work, "patches manifest data\n", success=success)
            if case == "dangling-add-symlink":
                assert target.is_symlink() and os.readlink(target) == "absent"
            else:
                want = b"added file" if case == "copy" else changed if case == "replace" else b"keep" if copying else original
                assert target.read_bytes() == want, "target changed before validation"
            if case == "stale-candidate":
                assert candidate.read_bytes() == b"keep candidate"
            if case == "candidate-symlink":
                assert candidate.is_symlink()
        record("patch-" + case, patch_case)

    for kind in ("external-existing", "symlink-target", "symlink-parent", "dot-alias", "dot-dot-alias",
                 "repeated-slash", "trailing-slash", "checkout-root", "build-out-parent",
                 "internal-reuse", "external-new"):
        def buildroot_case(kind=kind):
            outer = new("buildroot-" + kind)
            checkout = outer / "checkout"
            checkout.mkdir()
            (checkout / "tools").mkdir()
            (checkout / "tools/amd64.recipe").write_text('text "${W}/made" "done"\n')
            outputs = checkout / "build-out"
            outputs.mkdir()
            victim = outputs / "victim"
            victim.mkdir()
            (victim / "preserve").write_bytes(b"preserve these bytes")
            external = outer / "external"
            external.mkdir()
            (external / "preserve").write_bytes(b"external bytes")
            target = str(victim)
            if kind == "external-existing":
                target = str(external)
            elif kind == "symlink-target":
                (outputs / "link").symlink_to(external, target_is_directory=True)
                target = str(outputs / "link")
            elif kind == "symlink-parent":
                (checkout / "alias").symlink_to(outputs, target_is_directory=True)
                target = str(checkout / "alias/victim")
            elif kind == "dot-alias":
                target = str(outputs) + "/./victim"
            elif kind == "dot-dot-alias":
                target = str(victim) + "/../victim"
            elif kind == "repeated-slash":
                target = str(outputs) + "//victim"
            elif kind == "trailing-slash":
                target = str(victim) + "/"
            elif kind == "checkout-root":
                target = str(checkout)
            elif kind == "build-out-parent":
                target = str(outputs)
            elif kind == "external-new":
                target = str(outer / "fresh")
            before = snapshot(outer)
            run = launch(checkout, target, base / ("launch-" + kind))
            success = kind in ("internal-reuse", "external-new")
            assert (run.returncode == 0) == success, (run.returncode, run.stderr.decode(errors="replace"))
            if success:
                assert (Path(target) / "made").read_bytes() == b"done"
                assert (external / "preserve").read_bytes() == b"external bytes"
            else:
                assert snapshot(outer) == before, "rejected BUILDROOT changed fixtures"
        record("BUILDROOT-" + kind, buildroot_case)

print(f"amd64-runner checks: {len(passed)} PASS, {len(failed)} FAIL")
if failed:
    raise SystemExit(1)
