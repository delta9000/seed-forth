#!/usr/bin/env python3
"""seed-cc runtime cache: cold-cache concurrency, corruption and invalidation.

Modelled on driver-cache-check.py, for the native driver. In an isolated
source-copy fixture, seed-cc is bootstrapped by `./seed-forth <
tools/seed-cc-start.fth`; then eight seed-cc processes start together on an
absent runtime cache. All must succeed with identical executables, equal to
the Python driver's, while user -D/-I options must not leak into the
runtime build. Damaged objects or manifests are never trusted or
overwritten, and any input change selects a new cache identity. Only cache
bytes, one header comment, one driver comment and the seed are mutated.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, cwd, success=True):
    result = subprocess.run([str(part) for part in command], cwd=cwd, capture_output=True, timeout=900)
    if success:
        assert (result.returncode, result.stderr) == (0, b""), (command, result)
    return result


def make_fixture(fixture):
    names = ["000-seed.hex0", "seed-forth", "010-lib.fth", "141-archive.fth",
             "tools/gcc-direct-cc.py", "tools/seed-cc.c", "tools/seed-ar.c",
             "tools/seed-tool.h", "tools/seed-cc-start.fth"]
    names += [p.name for p in ROOT.glob("[0-9][0-9][0-9]-cc-*.fth")]
    names += [str(p.relative_to(ROOT)) for p in (ROOT / "tools/seed-cc-boot").glob("*.fth")]
    names += [str(p.relative_to(ROOT)) for p in (ROOT / "runtime/gcc-seed").rglob("*")
              if p.is_file() and p.suffix in (".c", ".h")]
    data = {name: (ROOT / name).read_bytes() for name in names}
    assert all((ROOT / name).read_bytes() == data[name] for name in names), "source changed during capture"
    for name in names:
        target = fixture / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data[name])
        target.chmod((ROOT / name).stat().st_mode & 0o777)


def manifest_ok(cache, identity):
    lines = (cache / "manifest").read_text().splitlines()
    assert lines[:2] == ["seed-cc runtime cache 1", "identity " + identity], lines[:2]
    for line in lines[2:]:
        digest, name = line.split(" ", 1)
        assert sha(cache / name) == digest, name
    return len(lines) - 2


def main():
    (ROOT / "build-out").mkdir(exist_ok=True)
    fixture = Path(tempfile.mkdtemp(prefix="seed-cc-cache-", dir=ROOT / "build-out"))
    try:
        make_fixture(fixture)
        with (fixture / "tools/seed-cc-start.fth").open("rb") as start:
            boot = subprocess.run(["./seed-forth"], cwd=fixture, stdin=start, capture_output=True, timeout=3600)
        assert (boot.returncode, boot.stdout, boot.stderr) == (0, b"", b""), boot
        driver = fixture / "build-out/seed-cc/seed-cc"
        # No includes: the runtime's own headers must not see the user's options.
        (fixture / "probe.c").write_text('int puts(const char *s);\nint main(void) { return puts("42") < 0; }\n')
        (fixture / "fake-headers").mkdir()
        (fixture / "fake-headers/stddef.h").write_text("#error user include leaked into runtime\n")
        cache_root = fixture / "build-out/seed-cc-cache"
        assert not cache_root.exists()

        def execute(name):
            result = subprocess.run([fixture / name], capture_output=True, timeout=10)
            assert (result.returncode, result.stdout, result.stderr) == (0, b"42\n", b""), (name, result)

        def compile_cold(index):
            run([driver, "-DSEED_GCC_STDDEF_H", "-Ifake-headers", "probe.c", "-o", f"probe-{index}"], fixture)
            execute(f"probe-{index}")
        with ThreadPoolExecutor(max_workers=8) as executor:
            list(executor.map(compile_cold, range(8)))
        identity = run([driver, "--print-source-hash"], fixture).stdout.decode().strip()
        entries = sorted(p.name for p in cache_root.iterdir())
        assert entries == [identity], entries
        cache = cache_root / identity
        objects = manifest_ok(cache, identity)
        binary = sha(fixture / "probe-0")
        assert all(sha(fixture / f"probe-{index}") == binary for index in range(8))
        run([sys.executable, fixture / "tools/gcc-direct-cc.py", "probe.c", "-o", "probe-python"], fixture)
        assert sha(fixture / "probe-python") == binary, "seed-cc and Python driver executables differ"

        # Damaged cached bytes never reach the linker and are not overwritten:
        # concurrent invocations rebuild privately and discard their staging.
        (cache / "memory.o").write_bytes(b"deliberately damaged cache object")
        def compile_damaged(index):
            run([driver, "probe.c", "-o", f"damaged-{index}"], fixture)
            execute(f"damaged-{index}")
        with ThreadPoolExecutor(max_workers=4) as executor:
            list(executor.map(compile_damaged, range(4)))
        assert all(sha(fixture / f"damaged-{index}") == binary for index in range(4))
        assert (cache / "memory.o").read_bytes() == b"deliberately damaged cache object"
        assert not list(cache_root.glob(".build-*")), "cache staging directory leaked"
        shutil.rmtree(cache)

        # A truncated or edited manifest is equally untrusted.
        run([driver, "probe.c", "-o", "rebuilt"], fixture)
        manifest = (cache / "manifest").read_bytes()
        (cache / "manifest").write_bytes(manifest[:-20])
        run([driver, "probe.c", "-o", "after-manifest"], fixture)
        (cache / "manifest").write_bytes(manifest.replace(b"identity ", b"identity 0"))
        run([driver, "probe.c", "-o", "after-identity"], fixture)
        assert sha(fixture / "after-manifest") == sha(fixture / "after-identity") == binary

        # Any runtime header or driver source change selects a new identity.
        header = fixture / "runtime/gcc-seed/include/stddef.h"
        header.write_bytes(header.read_bytes() + b"\n/* cache invalidation fixture */\n")
        changed = run([driver, "--print-source-hash"], fixture).stdout.decode().strip()
        assert changed != identity
        run([driver, "probe.c", "-o", "changed-header"], fixture)
        execute("changed-header")
        manifest_ok(cache_root / changed, changed)
        source = fixture / "tools/seed-cc.c"
        source.write_bytes(source.read_bytes() + b"/* identity fixture */\n")
        assert run([driver, "--print-source-hash"], fixture).stdout.decode().strip() not in (identity, changed)

        # A changed seed executable cannot be silently substituted.
        seed = fixture / "seed-forth"
        seed.write_bytes(seed.read_bytes() + b"bad")
        result = run([driver, "-c", "probe.c", "-o", "blocked.o"], fixture, success=False)
        assert result.returncode and b"does not match 000-seed.hex0" in result.stderr, result
        assert not (fixture / "blocked.o").exists()
        print(f"PASS: seed-cc cold-cache concurrency (8 processes, {objects} runtime objects, = Python driver),")
        print("      runtime flag/include isolation, damaged object/manifest rejection without overwrite,")
        print("      header/driver identity invalidation and seed byte verification")
    finally:
        shutil.rmtree(fixture, ignore_errors=True)


if __name__ == "__main__":
    main()
