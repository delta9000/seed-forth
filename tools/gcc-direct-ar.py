#!/usr/bin/env python3
"""Fresh deterministic GNU ar archives built entirely by seed Forth.

Bounded build adapter, not an incremental ar replacement. rc/rcs (optional D)
create a fresh archive; s validates its already-present GNU index. Existing
archives are never silently recreated by rc. Remove them explicitly first.
"""
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LAYERS = ("010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth",
          "140-cc-link.fth", "141-archive.fth")


def path_word(name, path):
    raw = os.fsencode(path)
    if not raw or b"\0" in raw or len(raw) > 4069:
        raise ValueError("invalid or overlong path")
    return f"create {name} " + " ".join(f"[lit] {b} c," for b in raw) + " [lit] 0 c,\n"


def main(args):
    if args == ["--version"]:
        print("gcc-direct-ar: Forth indexed archive adapter 1")
        return 0
    if len(args) < 2:
        raise ValueError("usage: gcc-direct-ar.py rc[s][D] ARCHIVE OBJECT... | s[D] ARCHIVE")
    flags = args[0].removeprefix("-")
    if len(set(flags)) != len(flags) or set(flags) - set("rcsD"):
        raise ValueError("supported operations: rc[s][D] fresh creation, s[D] index validation")
    create = "r" in flags and "c" in flags
    check = "s" in flags and not (set(flags) & set("rc"))
    if not create and not check:
        raise ValueError("fresh creation requires both r and c")
    output = Path(args[1]).absolute()
    inputs = [Path(p).absolute() for p in args[2:]]
    if check and inputs:
        raise ValueError("index validation accepts one archive and no objects")
    if create and os.path.lexists(output):
        raise ValueError("fresh creation requires a nonexistent output; remove the old archive explicitly")
    names = ["000-seed.hex0", "seed-forth", "tools/gcc-direct-ar.py", *LAYERS]
    snapshot = {name: (ROOT / name).read_bytes() for name in names}
    if any((ROOT / name).read_bytes() != data for name, data in snapshot.items()):
        raise ValueError("archive tool inputs changed during snapshot; retry")
    hexadecimal = b"".join(re.split(rb"[;#]", line, 1)[0]
                           for line in snapshot["000-seed.hex0"].splitlines())
    if bytes.fromhex(hexadecimal.decode("ascii")) != snapshot["seed-forth"]:
        raise ValueError("seed-forth does not match 000-seed.hex0; rebuild with build.sh")
    payloads = [(path, path.read_bytes()) for path in (inputs if create else [output])]
    if any(path.read_bytes() != data for path, data in payloads):
        raise ValueError("archive inputs changed during snapshot; retry")
    creation_mask = os.umask(0)
    os.umask(creation_mask)
    with tempfile.TemporaryDirectory(prefix="seed-ar-") as directory:
        work = Path(directory)
        seed = work / "seed-forth"
        seed.write_bytes(snapshot["seed-forth"])
        seed.chmod(0o700)
        private_output = work / "archive.a"
        code = "\n".join(snapshot[layer].decode() for layer in LAYERS) + "\narc-init\n"
        code += path_word("archive-output", private_output)
        for i, (path, data) in enumerate(payloads):
            folder = work / str(i)
            folder.mkdir()
            captured = folder / path.name
            captured.write_bytes(data)
            code += path_word(f"archive-input-{i}", captured)
            code += f"archive-input-{i} {'arc-add-object' if create else 'arc-check'}\n"
        if create:
            code += "archive-output arc-write\n"
        code += "bye\n"
        result = subprocess.run([seed], input=code.encode(), capture_output=True)
        if result.stdout:
            sys.stderr.buffer.write(result.stdout)
        if result.stderr:
            sys.stderr.buffer.write(result.stderr)
        if result.returncode or result.stdout:
            return result.returncode if result.returncode > 0 else 1
        if create:
            # Publish an exclusively created name; a racing output never gets
            # replaced. The temporary is on the destination filesystem.
            with tempfile.NamedTemporaryFile(prefix=".seed-ar-", dir=output.parent, delete=False) as stream:
                temporary = Path(stream.name)
                try:
                    stream.write(private_output.read_bytes())
                    stream.flush()
                    os.fchmod(stream.fileno(), 0o666 & ~creation_mask)
                    os.fsync(stream.fileno())
                    os.link(temporary, output)
                finally:
                    temporary.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError) as error:
        print(f"gcc-direct-ar: {error}", file=sys.stderr)
        sys.exit(2)
