#!/usr/bin/env python3
"""Compile two C translation units and link them with the seed's Forth tools.

No host C compiler, assembler, or linker makes an input or output artifact.
The test deliberately has colliding static names and an eight-argument call.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
(ROOT / "build-out").mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix="linker-c-", dir=ROOT / "build-out"))
for part in ("caller", "provider"):
    command = [ROOT / "tests/gcc/sysv-object-compile.sh",
               ROOT / f"tests/gcc/linker-c-{part}.c", OUT / f"{part}.o"]
    result = subprocess.run(command, capture_output=True, timeout=60)
    assert result.returncode == 0, (part, result.stdout, result.stderr)
    assert not result.stdout and not result.stderr, (part, result.stdout, result.stderr)

base = "\n".join((ROOT / p).read_text() for p in
                 ("010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth"))
program = base + "\n" + (ROOT / "081-cc-object.fth").read_text()
program += f"""
create start-path s, {OUT / 'start.o'} [lit] 0 c,
create start-name s, _start
create main-name s, main
variable main-id
cc-obj-init
[lit] 232 cc-obj-byte [lit] 0 cc-obj-4le
[lit] 137 cc-obj-byte [lit] 199 cc-obj-byte
[lit] 184 cc-obj-byte [lit] 60 cc-obj-4le
[lit] 15 cc-obj-byte [lit] 5 cc-obj-byte
start-name [lit] 6 cc-obj-global cc-obj-func cc-obj-default
cc-obj-text [lit] 0 [lit] 14 cc-obj-symbol drop
main-name [lit] 4 cc-obj-global cc-obj-func cc-obj-default
cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol main-id !
cc-obj-text [lit] 1 cc-obj-plt32 main-id @ [lit] 0 [lit] 4 - cc-obj-reloc
start-path cc-obj-write
"""
result = subprocess.run([ROOT / "seed-forth"], input=program.encode(), capture_output=True, timeout=30)
assert result.returncode == 0 and not result.stdout and not result.stderr, result

for order in (("start", "caller", "provider"), ("provider", "caller", "start")):
    output = OUT / ("-".join(order) + ".exe")
    program = base + "\n" + (ROOT / "140-cc-link.fth").read_text() + "\nlnk-init\n"
    for part in order:
        program += f"create {part}-path s, {OUT / (part + '.o')} [lit] 0 c,\n"
        program += f"{part}-path lnk-add-object\n"
    program += "create entry-name s, _start\nentry-name [lit] 6 lnk-entry\n"
    program += f"create output-path s, {output} [lit] 0 c,\noutput-path lnk-link\n"
    result = subprocess.run([ROOT / "seed-forth"], input=program.encode(), capture_output=True, timeout=30)
    assert result.returncode == 0 and not result.stdout and not result.stderr, result
    result = subprocess.run([output], capture_output=True, timeout=5)
    assert result.returncode == 42, (order, result.returncode, result.stdout, result.stderr)
print(f"linker-c: separate C objects execute42 in both input orders; proof artifacts: {OUT}")
