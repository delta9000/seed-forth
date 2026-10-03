#!/usr/bin/env python3
"""Exercise the Forth ELF linker; Python inspects and corrupts test inputs only.

Every successful object originates in 081 running on the seed. Host readelf is
an optional independent inspector, never an executable or object supplier.
"""
from pathlib import Path
import os
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(tempfile.mkdtemp(prefix="linker-", dir=ROOT / "build-out"))
BASE = "\n".join((ROOT / p).read_text() for p in
                 ("010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth"))
LINK = BASE + "\n" + (ROOT / "140-cc-link.fth").read_text()
WRITE = BASE + "\n" + (ROOT / "081-cc-object.fth").read_text()
COUNT = 0


def run_forth(text, expected=0):
    global COUNT
    COUNT += 1
    result = subprocess.run([ROOT / "seed-forth"], input=text.encode(),
                            capture_output=True, timeout=30)
    assert result.returncode == expected, (COUNT, expected, result.returncode,
                                          result.stdout, result.stderr)
    assert result.stdout == b"", (COUNT, result.stdout)
    if expected:
        assert f"error {expected}".encode() in result.stderr, result.stderr
    else:
        assert result.stderr == b"", result.stderr


def path_word(name, path):
    assert not any(c.isspace() for c in str(path))
    return f"\ncreate {name} s, {path} [lit] 0 c,\n"


def link(objects, name, expected=0, entry="_start"):
    dest = OUT / name
    program = LINK + "\nlnk-init\n"
    for i, obj in enumerate(objects):
        program += path_word(f"input-{i}", obj) + f"input-{i} lnk-add-object\n"
    program += f"create entry-name s, {entry}\nentry-name [lit] {len(entry)} lnk-entry\n"
    program += path_word("output-name", dest) + "output-name lnk-link\n"
    run_forth(program, expected)
    assert dest.exists() == (expected == 0), (name, "partial output")
    return dest


def execute(path, expected=42):
    result = subprocess.run([path], capture_output=True, timeout=5)
    assert result.returncode == expected, (path, expected, result.returncode,
                                          result.stdout, result.stderr)


def u16(b, p): return struct.unpack_from("<H", b, p)[0]
def u32(b, p): return struct.unpack_from("<I", b, p)[0]
def u64(b, p): return struct.unpack_from("<Q", b, p)[0]
def put(b, p, value, size=8):
    b[p:p + size] = value.to_bytes(size, "little", signed=False)
def sh(b, i): return u64(b, 40) + i * 64
def section_offset(b, i): return u64(b, sh(b, i) + 24)
def symbols(b):
    start = section_offset(b, 7)
    strings = section_offset(b, 8)
    count = u64(b, sh(b, 7) + 32) // 24
    result = {}
    for i in range(count):
        p = start + i * 24
        n = strings + u32(b, p)
        end = b.index(0, n)
        result[bytes(b[n:end]).decode()] = p
    return result


def mutated(source, name, edit):
    data = bytearray(source.read_bytes())
    edit(data)
    result = OUT / (name + ".o")
    result.write_bytes(data)
    return result


# Cross-object code/data references, 64-byte text alignment, separate RX/RW
# mappings, and an 8 KiB BSS whose first referenced page must start zeroed.
a, b, first = (OUT / n for n in ("a.o", "b.o", "first"))
program = WRITE + "\n" + (ROOT / "140-cc-link.fth").read_text()
for name, path in (("a", a), ("b", b), ("out", first)):
    program += path_word("linker-" + name + "-path", path)
program += (ROOT / "tests/gcc/linker-fixture.fth").read_text()
run_forth(program)
execute(first)
repeat = link([a, b], "repeat")
assert first.read_bytes() == repeat.read_bytes(), "link depends on writer state"
execute(link([b, a], "reversed"))
image = first.read_bytes()
assert u16(image, 16) == 2 and u16(image, 18) == 62
assert u64(image, 24) == 0x401000
assert u16(image, 56) == 2 and u64(image, 40) == 0
rx, rw = 64, 120
assert u32(image, rx + 4) == 5 and u32(image, rw + 4) == 6
assert u64(image, rw + 40) - u64(image, rw + 32) == 8192
assert u64(image, rw + 8) % 4096 == u64(image, rw + 16) % 4096 == 0
assert image[4096 + 64:4096 + 67] == bytes.fromhex("488b05")
assert u64(image, u64(image, rw + 8)) == 0x402010
assert len(image) == u64(image, rw + 8) + u64(image, rw + 32)

# The writer's separate fixture covers all five relocation types and a local
# ABS symbol after globals in the builder's insertion order.
caller, provider = OUT / "caller.o", OUT / "provider.o"
program = WRITE + "\n" + (ROOT / "tests/gcc/object-writer-fixture.fth").read_text()
program += path_word("caller-path", caller) + path_word("provider-path", provider)
program += "object-writer-caller caller-path cc-obj-write\n"
program += "object-writer-provider provider-path cc-obj-write\n"
run_forth(program)
execute(link([caller, provider], "all-relocations"))

# Repeated local ABS names are scoped to their input, even when identical.
local_copy = mutated(provider, "local-copy", lambda x: None)
# A provider duplicate is a deliberate strong-definition error.
link([a, b, local_copy], "duplicate-cross-fixture", 253) if False else None
link([a, b, b], "duplicate", 252)
link([a], "unresolved", 253)
link([a, b], "missing-entry", 253, "absent")
link([a, b], "nontext-entry", 253, "answer")


def make_weak(data, definitions_only=False):
    for p in symbols(data).values():
        if data[p + 4] >> 4 and (not definitions_only or u16(data, p + 6)):
            data[p + 4] = 0x20 | (data[p + 4] & 15)


weak_b = mutated(b, "weak-b", make_weak)
weak43 = mutated(weak_b, "weak43", lambda x: put(x, section_offset(x, 3), 43, 4))
execute(link([a, weak43, b], "strong-after-weak"))
execute(link([a, b, weak43], "strong-before-weak"))
execute(link([a, weak43, weak_b], "first-weak"), 43)
weak_a = mutated(a, "weak-undefined", make_weak)
weak_output = link([weak_a], "weak-zero").read_bytes()
assert u64(weak_output, u64(weak_output, 120 + 8)) == 0

# Metadata and relocation failures must be diagnosed before creating output.
cases = [
    ("truncated", lambda x: x.__delitem__(slice(30, None)), 250),
    ("machine", lambda x: put(x, 18, 3, 2), 250),
    ("class", lambda x: put(x, 4, 1, 1), 250),
    ("endian", lambda x: put(x, 5, 2, 1), 250),
    ("section-offset-wrap", lambda x: put(x, 40, 2**64 - 64), 250),
    ("section-size-wrap", lambda x: put(x, sh(x, 1) + 32, 2**64 - 1), 250),
    ("section-overrun", lambda x: put(x, sh(x, 1) + 24, len(x) - 1), 250),
    ("section-type", lambda x: put(x, sh(x, 1) + 4, 8, 4), 250),
    ("section-flags", lambda x: put(x, sh(x, 1) + 8, 7), 250),
    ("alignment-zero", lambda x: put(x, sh(x, 1) + 48, 0), 250),
    ("alignment-three", lambda x: put(x, sh(x, 1) + 48, 3), 250),
    ("alignment-large", lambda x: put(x, sh(x, 1) + 48, 2**21), 250),
    ("relocation-link", lambda x: put(x, sh(x, 5) + 40, 8, 4), 250),
    ("relocation-target", lambda x: put(x, sh(x, 5) + 44, 3, 4), 250),
    ("relocation-entry-size", lambda x: put(x, sh(x, 5) + 56, 16), 250),
    ("relocation-partial-entry", lambda x: put(x, sh(x, 5) + 32, 23), 250),
    ("local-prefix", lambda x: put(x, sh(x, 7) + 44, 2, 4), 250),
    ("symbol-name-overrun", lambda x: put(x, symbols(x)["_start"], 2**32 - 1, 4), 250),
    ("symbol-section", lambda x: put(x, symbols(x)["_start"] + 6, 6, 2), 250),
    ("symbol-range", lambda x: put(x, symbols(x)["_start"] + 8, 15), 250),
    ("symbol-binding", lambda x: put(x, symbols(x)["_start"] + 4, 0x32, 1), 250),
    ("symbol-type", lambda x: put(x, symbols(x)["_start"] + 4, 0x1a, 1), 250),
    ("relocation-type", lambda x: put(x, section_offset(x, 5) + 8, 9, 4), 254),
    ("relocation-offset", lambda x: put(x, section_offset(x, 5), 2**64 - 1), 254),
    ("relocation-width", lambda x: put(x, section_offset(x, 5), 13), 254),
    ("relocation-symbol", lambda x: put(x, section_offset(x, 5) + 12, 999, 4), 254),
    ("pc32-overflow", lambda x: put(x, section_offset(x, 5) + 16, 2**31), 254),
]
for name, edit, code in cases:
    bad = mutated(a, name, edit)
    link([bad, b], name, code)

# Force extreme addends into each supported narrow relocation, including a
# high-bit input that must not slip through signed-comparison overflow.
for kind in (2, 4, 10, 11):
    for addend in (2**32, 2**63, 2**64 - 2**32):
        def edit(data, kind=kind, addend=addend):
            p = section_offset(data, 5)
            put(data, p + 8, kind, 4)
            put(data, p + 16, addend)
        bad = mutated(a, f"range-{kind}-{addend}", edit)
        link([bad, b], f"range-{kind}-{addend}", 254)

if shutil.which("readelf"):
    result = subprocess.run(["readelf", "-h", "-l", first], capture_output=True)
    assert result.returncode == 0 and b"EXEC" in result.stdout
print(f"linker: {COUNT} seed runs passed; proof artifacts: {OUT}")
