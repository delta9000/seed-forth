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
(ROOT / "build-out").mkdir(exist_ok=True)
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
    previous = dest.read_bytes() if dest.exists() else None
    program = LINK + "\nlnk-init\n"
    for i, obj in enumerate(objects):
        program += path_word(f"input-{i}", obj) + f"input-{i} lnk-add-object\n"
    program += f"create entry-name s, {entry}\nentry-name [lit] {len(entry)} lnk-entry\n"
    program += path_word("output-name", dest) + "output-name lnk-link\n"
    run_forth(program, expected)
    if expected and previous is not None:
        assert dest.read_bytes() == previous, (name, "old output changed")
    else:
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
all_reloc = link([caller, provider], "all-relocations")
execute(all_reloc)
all_bytes = all_reloc.read_bytes()
all_data = u64(all_bytes, 120 + 8)
assert u32(all_bytes, all_data + 8) == 42
assert u32(all_bytes, all_data + 12) == 2**32 - 1

# A provider duplicate is a deliberate strong-definition error.
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
    ("osabi", lambda x: put(x, 7, 255, 1), 250),
    ("ident-padding", lambda x: put(x, 8, 1, 1), 250),
    ("program-header-size", lambda x: put(x, 54, 56, 2), 250),
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
    ("symbol-name-unterminated", lambda x: x.__setitem__(slice(section_offset(x, 8) + 1, section_offset(x, 8) + u64(x, sh(x, 8) + 32)), b"X" * (u64(x, sh(x, 8) + 32) - 1)), 250),
    ("section-name-overrun", lambda x: put(x, sh(x, 1), 2**32 - 1, 4), 250),
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

# Failed validation and file alias checks must preserve existing contents.
(OUT / "preserve").write_bytes(b"previous output survives\n")
link([a], "preserve", 253)
bad_reloc = mutated(a, "preserve-reloc", lambda x: put(x, section_offset(x, 5) + 8, 9, 4))
link([bad_reloc, b], "preserve", 254)
link([a, b], "a.o", 255)
os.link(a, OUT / "hardlink.o")
link([a, b], "hardlink.o", 255)
(OUT / "symlink.o").symlink_to(a)
link([a, b], "symlink.o", 255)
link([a, b], "preserve")
execute(OUT / "preserve")
assert not list(OUT.glob("*.lnk-*")), "temporary output leaked"

# A session may link twice or be reset repeatedly. New sessions may reuse
# names, but must not retain definitions from earlier inputs.
reused = [OUT / f"reuse-{i}" for i in range(4)]
program = LINK + path_word("input-a", a) + path_word("input-b", b)
program += "create entry-name s, _start\n"
for i, path in enumerate(reused):
    program += path_word(f"reuse-out-{i}", path)
program += "lnk-init input-a lnk-add-object input-b lnk-add-object\n"
program += "entry-name [lit] 6 lnk-entry reuse-out-0 lnk-link reuse-out-1 lnk-link\n"
program += "lnk-init lnk-init input-b lnk-add-object input-a lnk-add-object\n"
program += "entry-name [lit] 6 lnk-entry reuse-out-2 lnk-link\n"
program += "lnk-init input-a lnk-add-object entry-name [lit] 6 lnk-entry reuse-out-3 lnk-link\n"
run_forth(program, 253)
assert reused[0].read_bytes() == reused[1].read_bytes() == first.read_bytes()
execute(reused[2])
assert not reused[3].exists(), "old global definition survived reset"

# A pure text object exercises an empty RW segment. A second object contains
# an identically named local ABS symbol whose value must remain independent.
pure, local = OUT / "pure.o", OUT / "local.o"
program = WRITE + path_word("pure-path", pure) + path_word("local-path", local)
program += """
create pure-start s, _start
create pure-local s, private_answer
variable pure-id
cc-obj-init
[lit] 191 cc-obj-byte [lit] 0 cc-obj-4le
[lit] 184 cc-obj-byte [lit] 60 cc-obj-4le
[lit] 15 cc-obj-byte [lit] 5 cc-obj-byte
pure-start [lit] 6 cc-obj-global cc-obj-func cc-obj-default
cc-obj-text [lit] 0 [lit] 12 cc-obj-symbol drop
pure-local [lit] 14 cc-obj-local cc-obj-notype cc-obj-default
cc-obj-abs [lit] 42 [lit] 0 cc-obj-symbol pure-id !
cc-obj-text [lit] 1 cc-obj-r32 pure-id @ [lit] 0 cc-obj-reloc
pure-path cc-obj-write
cc-obj-init
pure-local [lit] 14 cc-obj-local cc-obj-notype cc-obj-default
cc-obj-abs [lit] 99 [lit] 0 cc-obj-symbol drop
local-path cc-obj-write
"""
run_forth(program)
execute(link([pure, local], "local-scope"))
execute(link([local, pure], "local-scope-reversed"))

# Exact signed/unsigned 32-bit boundaries are accepted, while the adjacent
# values are rejected. The patched operand is inspected rather than executed.
for kind, accepted in ((10, (0, 2**32 - 1)), (11, (2**31 - 1, 2**64 - 2**31))):
    for value in accepted:
        def boundary_edit(data, kind=kind, value=value):
            p = symbols(data)["private_answer"]
            put(data, p + 8, value)
            put(data, section_offset(data, 5) + 8, kind, 4)
        obj = mutated(pure, f"boundary-{kind}-{value}", boundary_edit)
        exe = link([obj], f"boundary-{kind}-{value}")
        assert u32(exe.read_bytes(), 4097) == value % 2**32
for kind, value in ((10, 2**32), (10, 2**64 - 1), (11, 2**31), (11, 2**64 - 2**31 - 1)):
    def bad_boundary(data, kind=kind, value=value):
        put(data, symbols(data)["private_answer"] + 8, value)
        put(data, section_offset(data, 5) + 8, kind, 4)
    obj = mutated(pure, f"bad-boundary-{kind}-{value}", bad_boundary)
    link([obj], f"bad-boundary-{kind}-{value}", 254)

if shutil.which("readelf"):
    result = subprocess.run(["readelf", "-h", "-l", first], capture_output=True)
    assert result.returncode == 0 and b"EXEC" in result.stdout
print(f"linker: {COUNT} seed runs passed; proof artifacts: {OUT}")
