#!/usr/bin/env python3
"""Cold-cache and corruption checks in an isolated source-copy fixture.

The fixture uses byte-identical project inputs and real Forth invocations.
Only cache bytes and one header comment are mutated, to test invalidation.
No host compiler or target-binary generator is used.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(driver, cwd, *arguments):
    result = subprocess.run([driver, *arguments], cwd=cwd, capture_output=True, timeout=60)
    assert (result.returncode, result.stderr) == (0, b""), (arguments, result)
    return result.stdout


def execute(path):
    result = subprocess.run([path], capture_output=True, timeout=10)
    assert (result.returncode, result.stdout, result.stderr) == (0, b"", b""), result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    with tempfile.TemporaryDirectory(prefix="driver-cache-") as directory:
        fixture = Path(directory)
        inputs = [ROOT / name for name in ("000-seed.hex0", "seed-forth", "010-lib.fth",
                                           "tools/gcc-direct-cc.py")]
        inputs += [p for p in ROOT.glob("[0-9][0-9][0-9]-cc-*.fth") if p.name != "120-cc-main.fth"]
        inputs += [p for p in (ROOT / "runtime/gcc-seed").rglob("*")
                   if p.is_file() and p.suffix in (".c", ".h")]
        data = {str(p.relative_to(ROOT)): p.read_bytes() for p in inputs}
        assert all(p.read_bytes() == data[str(p.relative_to(ROOT))] for p in inputs), "source changed during fixture capture"
        for path in inputs:
            target = fixture / path.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data[str(path.relative_to(ROOT))])
            target.chmod(path.stat().st_mode & 0o777)
        driver = fixture / "tools/gcc-direct-cc.py"
        (fixture / "probe.c").write_text("int main(void) { return 0; }\n")
        (fixture / "fake-headers").mkdir()
        (fixture / "fake-headers/stddef.h").write_text("#error user include leaked into runtime\n")

        # All four processes initially see the same absent runtime cache.
        # User definitions/includes would prevent the runtime from compiling
        # if they leaked across the runtime's fixed compilation boundary.
        def compile_cold(index):
            run(driver, fixture, "-DSEED_GCC_STDDEF_H", "-Ifake-headers", "probe.c", "-o", f"probe-{index}")
            execute(fixture / f"probe-{index}")
        with ThreadPoolExecutor(max_workers=4) as executor:
            list(executor.map(compile_cold, range(4)))

        identity = run(driver, fixture, "--print-source-hash").decode().strip()
        cache = fixture / "build-out/gcc-direct-cache" / identity
        manifest = json.loads((cache / "manifest.json").read_text())
        assert all(sha(cache / name) == expected for name, expected in manifest["artifact_sha256"].items())
        assert not list(cache.parent.glob(".build-*")), "cache staging directory leaked"
        assert manifest["source_sha256"]["tools/gcc-direct-cc.py"] == sha(driver)
        binary_hash = sha(fixture / "probe-0")
        assert all(sha(fixture / f"probe-{index}") == binary_hash for index in range(1, 4))

        # Unverified cached target bytes must never reach the Forth linker.
        (cache / "memory.o").write_bytes(b"deliberately damaged cache object")
        run(driver, fixture, "probe.c", "-o", "rebuilt")
        execute(fixture / "rebuilt")
        assert sha(fixture / "rebuilt") == binary_hash

        # Even a declaration-preserving header change invalidates the key.
        header = fixture / "runtime/gcc-seed/include/stddef.h"
        header.write_bytes(header.read_bytes() + b"\n/* cache invalidation fixture */\n")
        changed = run(driver, fixture, "--print-source-hash").decode().strip()
        assert changed != identity
        run(driver, fixture, "probe.c", "-o", "changed-header")
        execute(fixture / "changed-header")
        new_cache = cache.parent / changed
        new_manifest = json.loads((new_cache / "manifest.json").read_text())
        assert new_manifest["source_sha256"]["runtime/gcc-seed/include/stddef.h"] == sha(header)

        # A changed seed executable cannot be silently substituted.
        seed = fixture / "seed-forth"
        seed.write_bytes(seed.read_bytes() + b"bad")
        result = subprocess.run([driver, "-c", "probe.c", "-o", "blocked.o"], cwd=fixture, capture_output=True)
        assert result.returncode and b"does not match 000-seed.hex0" in result.stderr
        assert not (fixture / "blocked.o").exists()
        print("PASS: cold-cache concurrency, runtime flag/include isolation, cache corruption,")
        print("      header-key invalidation and seed/source byte verification")


if __name__ == "__main__":
    main()
