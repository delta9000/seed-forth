#!/usr/bin/env python3
"""Archive lazy-selection, malformed-envelope and publication boundary gate.

Fixtures are Forth-produced objects; Python mutations inject negative cases.
Host ar and ld are independent oracles, never target archive producers.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import runpy
from types import SimpleNamespace

s = SimpleNamespace(**runpy.run_path(str(Path(__file__).with_name("archive-check.py"))))
ROOT, OUT = s.ROOT, s.OUT
archive, link, execute, run, pathword = s.archive, s.link, s.execute, s.run, s.pathword
objects = s.objs
results = []

def record(name):
    results.append(name)

def ar_members(data):
    assert data[:8] == b"!<arch>\n"
    members = []
    p = 8
    while p < len(data):
        n = int(data[p + 48:p + 58])
        members.append((p, p + 60, n, data[p:p + 16].rstrip(b" ")))
        p += 60 + n + n % 2
    return members

def check_archive(path, expected=0):
    run(s.LOAD + "lnk-init\n" + pathword("check", path) + "check arc-check\n", expected)

def malformed(name, data, expected=250):
    bad = OUT / (name + ".a")
    bad.write_bytes(data)
    sentinel = OUT / (name + "-failed-output")
    sentinel.write_bytes(b"previous artifact survives\n")
    link(sentinel.name, [objects["start.o"], bad], expected)
    record(name)
    return bad

# Compare archive links with exactly the selected ordinary objects.
explicit = link("ordinary-selected", [objects["start.o"], objects["foo.o"]])
assert explicit.read_bytes() == (OUT / "basic").read_bytes()
record("ordinary-object-byte-identity")

# Reverse member order needs a second pass within the same archive.
# An archive before its demander is not automatically revisited.
link("archive-before-object", [s.a, objects["start.o"]], 253)
execute(link("repeated-archive", [s.a, objects["start.o"], s.a]))
libbar = archive("bar-only.a", [objects["bar.o"]])
libchain = archive("chain-only.a", [objects["chain.o"]])
link("cross-archive-order", [objects["start.o"], libbar, libchain], 253)
execute(link("cross-archive-repeat", [objects["start.o"], libbar, libchain, libbar]))
record("archive-position-and-explicit-repetition")

# A duplicate provider remains unused. Selecting a member for a second name
# imports all definitions, so a real duplicate strong definition still fails.
duplicate = archive("duplicate-unselected.a", [objects["foo.o"], objects["foo.o"]])
execute(link("duplicate-unselected", [objects["start.o"], duplicate]))
combo = OUT / "combo.o"
code = s.WRITE + "cc-obj-init\n"
code += "[lit] 184 cc-obj-byte [lit] 42 cc-obj-4le [lit] 195 cc-obj-byte\n"
for name in ("foo", "bar"):
    code += f"create combo-{name} s, {name}\ncombo-{name} [lit] 3 cc-obj-global cc-obj-func cc-obj-default cc-obj-text [lit] 0 [lit] 6 cc-obj-symbol drop\n"
run(code + pathword("combo-path", combo) + "combo-path cc-obj-write\n")
combo_lib = archive("combo.a", [combo])
link("selected-duplicate", [objects["start.o"], objects["chain.o"], combo_lib], 252)
record("selected-versus-unselected-duplicates")

# Weak undefined demand does not extract; a following strong reference must
# upgrade demand even when the weak reference arrived first.
weak_path, code = s.object_code("weak-reference.o", definition="_start", reference="foo", weakref=True, entry=True)
run(s.WRITE + "variable archive-ref\n" + code)
weak_without = link("weak-no-archive", [weak_path])
weak_with = link("weak-with-archive", [weak_path, s.a])
assert weak_with.read_bytes() == weak_without.read_bytes()
weak_only, code = s.object_code("weak-only-reference.o", reference="foo", weakref=True)
run(s.WRITE + "variable archive-ref\n" + code)
execute(link("weak-then-strong-demand", [weak_only, objects["start.o"], s.a]))
execute(link("selected-weak-then-strong-object", [objects["start.o"], OUT / "weak0.a", objects["foo.o"]]))
record("weak-demand-and-strong-upgrade")

# A corrupt relocation in an unused member must never be interpreted.
broken = OUT / "broken.o"
data = bytearray(objects["chain.o"].read_bytes())
shoff = int.from_bytes(data[40:48], "little")
rela = int.from_bytes(data[shoff + 5 * 64 + 24:shoff + 5 * 64 + 32], "little")
data[rela + 8:rela + 12] = (255).to_bytes(4, "little")
broken.write_bytes(data)
lazy = archive("unused-broken.a", [objects["foo.o"], broken])
execute(link("unused-broken", [objects["start.o"], lazy]))
selected_broken = archive("selected-broken.a", [broken, objects["bar.o"]])
link("selected-broken", [objects["start.o"], selected_broken], 254)
oracle = OUT / "unused-broken-ld"
p = subprocess.run(["ld", "-o", oracle, objects["start.o"], lazy], capture_output=True)
assert p.returncode == 0, p.stderr
execute(oracle)
record("unused-broken-relocation-remains-unselected")

# Unknown payload bytes are harmless if their indexed names are not needed.
unknown = bytearray(lazy.read_bytes())
members = ar_members(unknown)
p, payload, n, _ = members[-1]
unknown[payload:payload + 4] = b"BAD!"
unknown_path = OUT / "unused-unknown.a"
unknown_path.write_bytes(unknown)
execute(link("unused-unknown", [objects["start.o"], unknown_path]))
record("unused-unsupported-payload-remains-unselected")

# GNU-produced indexed archives are reader oracles, never Forth output inputs.
gnu = OUT / "gnu-reader.a"
gnu.unlink(missing_ok=True)
subprocess.run(["ar", "rcsD", gnu, objects["this_is_a_long_archive_member_filename.o"]], check=True)
execute(link("gnu-reader", [objects["start.o"], gnu]))
record("gnu-long-name-reader")

# Build a synthetic BSD extended name around the same Forth member bytes,
# retaining the portable GNU index. Its member header offset does not move.
bsd = bytearray(s.a.read_bytes())
p, payload, n, _ = ar_members(bsd)[1]
bname = b"bsd_extended_archive_member.o\0\0\0"
assert len(bname) % 2 == 0
bsd[p:p + 16] = (b"#1/" + str(len(bname)).encode()).ljust(16)
bsd[p + 48:p + 58] = str(n + len(bname)).encode().ljust(10)
bsd[payload:payload] = bname
bsd_path = OUT / "bsd-name.a"
bsd_path.write_bytes(bsd)
execute(link("bsd-name", [objects["start.o"], bsd_path]))
record("bsd-extended-name-reader")

base = s.a.read_bytes()
index_header, index_start, index_size, _ = ar_members(base)[0]
member_header, member_start, member_size, _ = ar_members(base)[1]
for name, data in (
    ("empty-input", b""),
    ("magic-truncated", base[:7]),
    ("thin-format", base.replace(b"!<arch>", b"!<thin>", 1)),
    ("header-truncated", base[:30]),
    ("payload-truncated", base[:-1]),
    ("trailing-junk", base + b"x"),
):
    malformed(name, data)

def mutate(name, start, replacement, expected=250):
    data = bytearray(base)
    data[start:start + len(replacement)] = replacement
    malformed(name, data, expected)

mutate("bad-header-trailer", 66, b"x")
mutate("negative-size", 56, b"-1        ")
mutate("nonnumeric-size", 56, b"12x       ")
mutate("oversized-size", 56, b"9999999999")
mutate("index-count-cap", index_start, (65537).to_bytes(4, "big"), 251)
mutate("index-count-overrun", index_start, (10).to_bytes(4, "big"))
mutate("index-member-misaligned", index_start + 4, (member_header + 1).to_bytes(4, "big"))
mutate("index-member-special", index_start + 4, index_header.to_bytes(4, "big"))
mutate("index-member-outside", index_start + 4, (len(base) + 1).to_bytes(4, "big"))
mutate("index-empty-name", index_start + 8, b"\0")
mutate("index-no-terminator", index_start + index_size - 1, b"x")
mutate("unsupported-index64", index_header, b"/SYM64/         ")
mutate("empty-member-name", member_header, b"                ")
mutate("unterminated-long-reference", member_header, b"/0              ")
mutate("unsupported-bsd-ranlib", member_header, b"__.SYMDEF/      ")

# Duplicate symbol indexes and missing indexes are explicit errors.
first_member = base[8:member_header]
malformed("duplicate-index", base[:member_header] + first_member + base[member_header:])
malformed("missing-index", base[:8] + base[member_header:])

# Odd member payloads require a newline pad, including an unused member.
odd = bytearray(lazy.read_bytes())
h, payload, n, _ = ar_members(odd)[-1]
assert n % 2 == 0
odd[h + 48:h + 58] = str(n - 1).encode().ljust(10)
odd[-1] = 10
oddpath = OUT / "odd-padding.a"
oddpath.write_bytes(odd)
execute(link("odd-unused", [objects["start.o"], oddpath]))
odd[-1] = 0
malformed("wrong-odd-padding", odd)
malformed("missing-odd-padding", odd[:-1])

# An archive that contributed no members still participates in output alias
# checks, including hard links and symbolic links.
for name, kind in (("archive-alias.a", "copy"), ("archive-hardlink.a", "hard"), ("archive-symlink.a", "sym")):
    alias = OUT / name
    alias.unlink(missing_ok=True)
    if kind == "copy": alias.write_bytes(base)
    elif kind == "hard": os.link(s.a, alias)
    else: alias.symlink_to(s.a)
    link(name, [objects["start.o"], objects["foo.o"], alias], 255)
record("input-archive-alias-preservation")

# Writer validation failure preserves pre-existing bytes as well.
invalid = OUT / "invalid-writer.o"
invalid.write_bytes(b"invalid")
old = OUT / "writer-preserve.a"
old.write_bytes(b"previous archive\n")
run(s.LOAD + "arc-init\n" + pathword("bad", invalid) + pathword("out", old) + "bad arc-add-object out arc-write\n", 250)
assert old.read_bytes() == b"previous archive\n"
record("writer-failure-preservation")

# Writer and reader agree on empty nonlocal names and BSD reserved names.
empty_name = bytearray(objects["foo.o"].read_bytes())
shoff = int.from_bytes(empty_name[40:48], "little")
symoff = int.from_bytes(empty_name[shoff + 7 * 64 + 24:shoff + 7 * 64 + 32], "little")
empty_name[symoff + 24:symoff + 28] = bytes(4)
empty_obj = OUT / "empty-symbol-name.o"
empty_obj.write_bytes(empty_name)
for bad in (empty_obj,):
    run(s.LOAD + "arc-init\n" + pathword("bad", bad) + pathword("out", old) + "bad arc-add-object out arc-write\n", 250)
    assert old.read_bytes() == b"previous archive\n"
for name in ("__.SYMDEF", "__.SYMDEF_64"):
    reserved = OUT / name
    reserved.write_bytes(objects["foo.o"].read_bytes())
    run(s.LOAD + "arc-init\n" + pathword("bad", reserved) + pathword("out", old) + "bad arc-add-object out arc-write\n", 250)
    assert old.read_bytes() == b"previous archive\n"
prefix_obj = OUT / "__.SYMDEFordinary.o"
prefix_obj.write_bytes(objects["foo.o"].read_bytes())
prefix_archive = archive("allowed-prefix.a", [prefix_obj])
check_archive(prefix_archive)
execute(link("allowed-prefix", [objects["start.o"], prefix_archive]))
record("writer-reader-name-validation-agreement")

# CLI validation, fresh creation and index validation require no host ar.
wrapper = ROOT / "tools/gcc-direct-ar.py"
cli = OUT / "wrapper.a"
cli.unlink(missing_ok=True)
subprocess.run([wrapper, "rcsD", cli, objects["foo.o"]], check=True)
assert cli.read_bytes() == base
masked = OUT / "umask-wrapper.a"
masked.unlink(missing_ok=True)
subprocess.run([wrapper, "rc", masked, objects["foo.o"]], check=True, umask=0o077)
assert masked.stat().st_mode & 0o777 == 0o600
before = cli.read_bytes()
subprocess.run([wrapper, "s", cli], check=True)
assert cli.read_bytes() == before
for flags in ("rcs", "q", "rcsx", "rrc", "r", "cru"):
    assert subprocess.run([wrapper, flags, cli, objects["foo.o"]], capture_output=True).returncode == 2
assert cli.read_bytes() == before
record("bounded-wrapper-and-existing-output-preservation")
assert not list(OUT.glob("*.lnk-*"))

report = {"scope": "Forth indexed archive and lazy selection gate; not full GCC", "passed": results,
          "sources": {f: hashlib.sha256((ROOT / f).read_bytes()).hexdigest() for f in ("140-cc-link.fth", "141-archive.fth", "tools/gcc-direct-ar.py")},
          "oracles": ["GNU ar", "readelf", "GNU ld"], "target_bytes": "seed Forth only"}
(OUT / "boundary-results.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"archive boundary: {len(results)} checks passed; {OUT / 'boundary-results.json'}")
