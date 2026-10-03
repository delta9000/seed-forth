#!/usr/bin/env python3
"""Independent ar/ld inspection of Forth archive bytes and lazy selection."""
import os
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build-out/gcc-archive"
OUT.mkdir(parents=True, exist_ok=True)
BASE = ["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth"]
LOAD = "\n".join((ROOT / x).read_text() for x in BASE + ["140-cc-link.fth", "141-archive.fth"]) + "\n"
WRITE = "\n".join((ROOT / x).read_text() for x in BASE + ["081-cc-object.fth"]) + "\n"
COUNT = 0

def pathword(name, path):
    return f"create {name} " + " ".join(f"[lit] {c} c," for c in os.fsencode(path)) + " [lit] 0 c,\n"

def run(code, expected=0):
    global COUNT
    COUNT += 1
    p = subprocess.run([ROOT / "seed-forth"], input=(code + "\nbye\n").encode(), capture_output=True)
    assert p.returncode == expected, (COUNT, p.returncode, expected, p.stdout, p.stderr)
    assert b"?" not in p.stdout, (COUNT, p.stdout)
    return p

def archive(name, objects):
    dest = OUT / name
    code = LOAD + "arc-init\n" + pathword("out", dest)
    for i, obj in enumerate(objects):
        code += pathword(f"obj{i}", obj) + f"obj{i} arc-add-object\n"
    run(code + "out arc-write\n")
    return dest

def link(name, inputs, expected=0):
    dest = OUT / name
    before = dest.read_bytes() if dest.exists() else None
    code = LOAD + "lnk-init\n" + pathword("out", dest)
    for i, obj in enumerate(inputs):
        word = "lnk-add-archive" if obj.suffix == ".a" else "lnk-add-object"
        code += pathword(f"obj{i}", obj) + f"obj{i} {word}\n"
    code += "create entry s, _start\nentry [lit] 6 lnk-entry out lnk-link\n"
    run(code, expected)
    if expected:
        assert (dest.read_bytes() if dest.exists() else None) == before
    return dest

def execute(path, expected=42):
    p = subprocess.run([path], capture_output=True)
    assert p.returncode == expected, (path.name, p.returncode, expected)

def object_code(filename, definition=None, reference=None, value=42, weak=False, weakref=False, local=False, entry=False):
    path = OUT / filename
    code = "cc-obj-init\n"
    if entry:
        payload = bytes.fromhex("e80000000089c7b83c0000000f05")
    elif reference:
        payload = bytes.fromhex("e800000000c3")
    else:
        payload = b"\xb8" + value.to_bytes(4, "little") + b"\xc3"
    for c in payload:
        code += f"[lit] {c} cc-obj-byte\n"
    if definition:
        code += f"create n{filename.replace('.', '_')} s, {definition}\n"
        binding = "local" if local else "weak" if weak else "global"
        code += f"n{filename.replace('.', '_')} [lit] {len(definition)} cc-obj-{binding} cc-obj-func cc-obj-default cc-obj-text [lit] 0 [lit] {len(payload)} cc-obj-symbol drop\n"
    if reference:
        code += f"create r{filename.replace('.', '_')} s, {reference}\n"
        code += f"r{filename.replace('.', '_')} [lit] {len(reference)} cc-obj-{'weak' if weakref else 'global'} cc-obj-func cc-obj-default cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol\n"
        code += "archive-ref ! cc-obj-text [lit] 1 cc-obj-plt32 archive-ref @ [lit] 0 [lit] 4 - cc-obj-reloc\n"
    code += pathword("path" + filename.replace('.', '_'), path) + "path" + filename.replace('.', '_') + " cc-obj-write\n"
    return path, code

specs = [
    ("start.o", dict(definition="_start", reference="foo", entry=True)),
    ("foo.o", dict(definition="foo")),
    ("chain.o", dict(definition="foo", reference="bar")),
    ("bar.o", dict(definition="bar")),
    ("weak.o", dict(definition="foo", weak=True, value=43)),
    ("local.o", dict(definition="foo", local=True, value=44)),
    ("this_is_a_long_archive_member_filename.o", dict(definition="foo")),
]
objs = {}
code = WRITE + "variable archive-ref\n"
for name, options in specs:
    objs[name], part = object_code(name, **options)
    code += part
run(code)
a = archive("basic.a", [objs["foo.o"]])
execute(link("basic", [objs["start.o"], a]))
first = a.read_bytes()
archive("basic.a", [objs["foo.o"]])
assert a.read_bytes() == first
b = archive("reverse-chain.a", [objs["bar.o"], objs["chain.o"]])
execute(link("reverse-chain", [objs["start.o"], b]))
for index, order in enumerate(([objs["weak.o"], objs["foo.o"]], [objs["foo.o"], objs["weak.o"]])):
    lib = archive(f"weak{index}.a", order)
    execute(link(f"weak{index}", [objs["start.o"], lib]), 43 if index == 0 else 42)
local = archive("local.a", [objs["local.o"], objs["foo.o"]])
execute(link("local", [objs["start.o"], local]))
long = archive("long.a", [objs["this_is_a_long_archive_member_filename.o"]])
execute(link("long", [objs["start.o"], long]))
for lib in (a, b, local, long):
    assert subprocess.run(["ar", "t", lib], capture_output=True).returncode == 0
    assert subprocess.run(["readelf", "-s", lib], capture_output=True).returncode == 0
    oracle = OUT / (lib.stem + "-host-ld")
    p = subprocess.run(["ld", "-o", oracle, objs["start.o"], lib], capture_output=True)
    assert p.returncode == 0, p.stderr
    execute(oracle)
print(f"archive: {COUNT} seed runs passed; proof artifacts: {OUT}")
