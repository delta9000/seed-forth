#!/usr/bin/env python3
"""Exercise the Forth writer; readelf and ld are independent test oracles."""
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
for tool in ("readelf", "ld"):
    if not shutil.which(tool):
        raise SystemExit(f"object-writer-check: test oracle missing: {tool}")
if not (ROOT / "seed-forth").is_file():
    raise SystemExit("object-writer-check: run ./build.sh first")
(ROOT / "build-out").mkdir(exist_ok=True)
OUT = pathlib.Path(tempfile.mkdtemp(prefix="object-writer-", dir=ROOT / "build-out"))
PRELUDE = b"".join((ROOT / name).read_bytes() for name in (
    "010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth", "081-cc-object.fth",
    "tests/gcc/object-writer-fixture.fth"))


def forth(name, body, status=0):
    source = PRELUDE + b"\n" + body.encode() + b"\nbye\n"
    result = subprocess.run([str(ROOT / "seed-forth")], input=source,
                            capture_output=True, timeout=30)
    if result.returncode != status or result.stdout:
        raise AssertionError((name, result.returncode, result.stdout, result.stderr))
    if status and f"error {status}\n".encode() not in result.stderr:
        raise AssertionError((name, "missing diagnostic", result.stderr))
    if not status and result.stderr:
        raise AssertionError((name, result.stderr))


def write_object(name, body):
    path = OUT / (name + ".o")
    forth(name, body + f"\ncreate ow-output s, {path} [lit] 0 c,\now-output cc-obj-write")
    return path


def read_object(path):
    """Read ABI records, independently of the writer's private Forth tables."""
    data = path.read_bytes()
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", data)
    assert header[0] == b"\x7fELF\x02\x01\x01" + b"\0" * 9
    assert header[1:7] == (1, 62, 1, 0, 0, header[6])
    assert header[7:13] == (0, 64, 0, 0, 64, 10)
    assert header[13] == 9
    rows = [struct.unpack_from("<IIQQQQIIQQ", data, header[6] + i * 64)
            for i in range(header[12])]
    assert rows[0] == (0,) * 10
    names_row = rows[header[13]]
    names = data[names_row[4]:names_row[4] + names_row[5]]
    sections = {}
    for index, row in enumerate(rows[1:], 1):
        name = names[row[0]:].split(b"\0", 1)[0].decode()
        assert row[3] == 0
        assert row[8] > 0 and row[8] & (row[8] - 1) == 0
        assert row[4] % row[8] == 0
        assert row[1] == 8 or row[4] + row[5] <= header[6]
        sections[name] = (index, row, data[row[4]:row[4] + row[5]])
    assert tuple(sections) == (".text", ".rodata", ".data", ".bss", ".rela.text",
                               ".rela.data", ".symtab", ".strtab", ".shstrtab")
    _, symrow, symdata = sections[".symtab"]
    assert symrow[6] == sections[".strtab"][0] and symrow[9] == 24
    strings = sections[".strtab"][2]
    symbols = []
    for i in range(0, len(symdata), 24):
        name, info, other, shndx, value, size = struct.unpack_from("<IBBHQQ", symdata, i)
        assert (info >> 4 == 0) == (i // 24 < symrow[7])
        symbols.append((strings[name:].split(b"\0", 1)[0].decode(),
                        info >> 4, info & 15, other, shndx, value, size))
    assert symbols[0] == ("", 0, 0, 0, 0, 0, 0)
    relocs = {}
    for target in ("text", "data"):
        _, row, payload = sections[".rela." + target]
        assert row[6] == sections[".symtab"][0]
        assert row[7] == sections["." + target][0] and row[9] == 24
        relocs[target] = []
        for pos in range(0, len(payload), 24):
            off, info, addend = struct.unpack_from("<QQq", payload, pos)
            relocs[target].append((off, info & 0xffffffff, symbols[info >> 32][0], addend))
    return sections, symbols, relocs


for name, operation in (("byte", "[lit] 195 cc-obj-byte"),
                        ("build", "cc-obj-build"),
                        ("select", "cc-obj-text cc-obj-use")):
    forth("uninitialized-" + name, operation, 244)

caller = write_object("caller", "object-writer-caller")
provider = write_object("provider", "object-writer-provider")
assert caller.stat().st_mode & 0o777 == 0o644
inspection = subprocess.run(["readelf", "-aW", str(caller)], check=True,
                            capture_output=True, text=True)
assert not inspection.stderr, inspection.stderr
(OUT / "caller.readelf.txt").write_text(inspection.stdout)
for expected in ("REL (Relocatable file)", "R_X86_64_PLT32", "R_X86_64_PC32",
                 "R_X86_64_64", "R_X86_64_32 ", "R_X86_64_32S", "local_answer"):
    assert expected in inspection.stdout, expected
executable = OUT / "cross-object"
subprocess.run(["ld", "-e", "_start", "-o", str(executable), str(caller), str(provider)], check=True)
run = subprocess.run([str(executable)], timeout=10)
assert run.returncode == 42, run.returncode
sections, symbols, relocs = read_object(caller)
assert symbols[1] == ("local_answer", 0, 0, 2, 65521, 42, 0)
assert relocs["text"] == [(6, 4, "triple", -4), (12, 2, "shared_value", -4)]
assert relocs["data"] == [(0, 1, "shared_value", 0), (8, 10, "local_answer", 0),
                          (12, 11, "local_answer", -43)]
empty = write_object("empty", "cc-obj-init")
reset_empty = write_object("reset-empty", "object-writer-caller cc-obj-build cc-obj-init")
assert empty.read_bytes() == reset_empty.read_bytes()
reset_zero = write_object("reset-zero", """
cc-obj-init cc-obj-data cc-obj-use true cc-obj-8le
cc-obj-init cc-obj-data cc-obj-use [lit] 8 cc-obj-reserve drop
""")
assert read_object(reset_zero)[0][".data"][2] == b"\0" * 8
forward = write_object("forward", """
cc-obj-init
ow-helper [lit] 6 cc-obj-local cc-obj-func cc-obj-default cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol
[lit] 195 cc-obj-byte
cc-obj-text [lit] 0 [lit] 1 cc-obj-define
""")
assert ("triple", 0, 2, 0, 1, 0, 1) in read_object(forward)[1]

metadata = write_object("metadata", """
cc-obj-init
[lit] 195 cc-obj-byte [lit] 16 cc-obj-align
cc-obj-rodata cc-obj-use [lit] 8 cc-obj-align [lit] 578437695752307201 cc-obj-8le
cc-obj-data cc-obj-use [lit] 16 cc-obj-reserve drop
[lit] 305419896 cc-obj-data [lit] 0 cc-obj-patch-4le
[lit] 18446744073709551615 cc-obj-data [lit] 8 cc-obj-patch-8le
cc-obj-bss cc-obj-use [lit] 4096 cc-obj-align [lit] 65536 cc-obj-reserve drop
create meta-weak s, weak_bss
meta-weak [lit] 8 cc-obj-weak cc-obj-object cc-obj-protected cc-obj-bss [lit] 0 [lit] 65536 cc-obj-symbol drop
create meta-hidden s, hidden_data
meta-hidden [lit] 11 cc-obj-local cc-obj-object cc-obj-hidden cc-obj-data [lit] 0 [lit] 4 cc-obj-symbol drop
create meta-internal s, internal_constant
meta-internal [lit] 17 cc-obj-global cc-obj-notype cc-obj-internal cc-obj-abs [lit] 18446744073709551615 [lit] 0 cc-obj-symbol drop
[lit] 0 [lit] 0 cc-obj-local cc-obj-section cc-obj-default cc-obj-text [lit] 0 [lit] 0 cc-obj-symbol drop
"""
)
meta_sections, meta_symbols, _ = read_object(metadata)
assert meta_sections[".text"][1][8] == 16
assert meta_sections[".text"][2] == b"\xc3" + b"\0" * 15
assert meta_sections[".rodata"][2] == bytes(range(1, 9))
assert meta_sections[".data"][2] == b"\x78\x56\x34\x12" + b"\0" * 4 + b"\xff" * 8
assert meta_sections[".bss"][1][1:3] == (8, 3)
assert meta_sections[".bss"][1][5] == 65536 and meta_sections[".bss"][1][8] == 4096
assert metadata.stat().st_size < 8192  # NOBITS is not silently written as zero payload.
assert ("weak_bss", 2, 1, 3, 4, 0, 65536) in meta_symbols
assert ("internal_constant", 1, 0, 1, 65521, 2**64 - 1, 0) in meta_symbols
assert ("", 0, 3, 0, 1, 0, 0) in meta_symbols
meta_readelf = subprocess.run(["readelf", "-aW", str(metadata)], check=True,
                              capture_output=True, text=True)
assert not meta_readelf.stderr, meta_readelf.stderr
(OUT / "metadata.readelf.txt").write_text(meta_readelf.stdout)

# Build twice, then reset and rebuild in the SAME Forth process. Copies and
# comparisons use the library rather than Python reproducing writer operations.
forth("reset-and-repeat", """
: ow-assert 0= if, [lit] 250 die then, ;
[lit] 314159
object-writer-caller cc-obj-build
cc-out-pos @ constant saved-size
create saved-object saved-size allot
variable copy-index
[lit] 0 copy-index !
: save-bytes
  begin, copy-index @ saved-size < while,
    cc-out-buf copy-index @ + c@ saved-object copy-index @ + c!
    [lit] 1 copy-index +!
  repeat, ;
save-bytes
cc-obj-build cc-out-pos @ saved-size = ow-assert
cc-out-buf saved-object saved-size bytes-eq ow-assert
cc-obj-init cc-obj-data cc-obj-use [lit] 16 cc-obj-reserve [lit] 0 = ow-assert
cc-obj-build
object-writer-caller cc-obj-build
cc-out-pos @ saved-size = ow-assert
cc-out-buf saved-object saved-size bytes-eq ow-assert
[lit] 314159 = ow-assert
"""
)

symbol = "ow-value [lit] 12 cc-obj-global cc-obj-notype cc-obj-default cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol"
bad = [
    ("section-zero", "[lit] 0 cc-obj-use", 244),
    ("section-five", "[lit] 5 cc-obj-use", 244),
    ("section-negative", "true cc-obj-use", 244),
    ("alignment-zero", "[lit] 0 cc-obj-align", 244),
    ("alignment-three", "[lit] 3 cc-obj-align", 244),
    ("alignment-large", "[lit] 8192 cc-obj-align", 244),
    ("negative-reserve", "true cc-obj-reserve", 245),
    ("section-cap", "cc-obj-section-cap cc-obj-reserve drop [lit] 1 cc-obj-byte", 245),
    ("bss-cap", "cc-obj-bss cc-obj-use cc-obj-bss-cap cc-obj-reserve drop [lit] 1 cc-obj-reserve", 245),
    ("bss-emission", "cc-obj-bss cc-obj-use [lit] 1 cc-obj-byte", 244),
    ("empty-patch", "[lit] 0 cc-obj-text [lit] 0 cc-obj-patch-4le", 244),
    ("straddling-patch", "[lit] 4 cc-obj-reserve drop [lit] 0 cc-obj-text [lit] 1 cc-obj-patch-4le", 244),
    ("negative-patch", "[lit] 8 cc-obj-reserve drop [lit] 0 cc-obj-text true cc-obj-patch-8le", 244),
    ("bss-patch", "[lit] 0 cc-obj-bss [lit] 0 cc-obj-patch-4le", 244),
    ("bad-binding", symbol.replace("cc-obj-global", "[lit] 3"), 246),
    ("bad-type", symbol.replace("cc-obj-notype", "[lit] 4"), 246),
    ("bad-visibility", symbol.replace("cc-obj-default", "[lit] 4"), 246),
    ("bad-symbol-section", symbol.replace("cc-obj-undef", "[lit] 5"), 246),
    ("undefined-value", symbol.replace("[lit] 0 [lit] 0 cc-obj-symbol", "[lit] 1 [lit] 0 cc-obj-symbol"), 246),
    ("empty-name", symbol.replace("[lit] 12", "[lit] 0"), 246),
    ("nul-in-name", "create bad-name [lit] 0 c, " + symbol.replace("ow-value [lit] 12", "bad-name [lit] 1"), 246),
    ("name-too-large", symbol.replace("[lit] 12", "cc-obj-string-cap"), 245),
    ("undefined-local", symbol.replace("cc-obj-global", "cc-obj-local") + " drop cc-obj-build", 246),
    ("symbol-extent", symbol.replace("cc-obj-undef [lit] 0 [lit] 0", "cc-obj-text [lit] 0 [lit] 1"), 246),
    ("define-zero", "[lit] 0 cc-obj-text [lit] 0 [lit] 0 cc-obj-define", 246),
    ("named-section-symbol", symbol.replace("cc-obj-notype", "cc-obj-section"), 246),
    ("redefine-section-abs", "[lit] 0 [lit] 0 cc-obj-local cc-obj-section cc-obj-default cc-obj-text [lit] 0 [lit] 0 cc-obj-symbol cc-obj-abs [lit] 0 [lit] 0 cc-obj-define", 244),
    ("reloc-kind", symbol + " drop [lit] 8 cc-obj-reserve drop cc-obj-text [lit] 0 [lit] 3 [lit] 1 [lit] 0 cc-obj-reloc", 247),
    ("reloc-rodata", symbol + " drop cc-obj-rodata [lit] 0 cc-obj-r32 [lit] 1 [lit] 0 cc-obj-reloc", 247),
    ("reloc-straddle", symbol + " drop [lit] 4 cc-obj-reserve drop cc-obj-text [lit] 1 cc-obj-r32 [lit] 1 [lit] 0 cc-obj-reloc", 247),
    ("reloc-width-eight", symbol + " drop [lit] 4 cc-obj-reserve drop cc-obj-text [lit] 0 cc-obj-r64 [lit] 1 [lit] 0 cc-obj-reloc", 247),
    ("reloc-negative", symbol + " drop cc-obj-text true cc-obj-r32 [lit] 1 [lit] 0 cc-obj-reloc", 247),
    ("reloc-id-zero", "cc-obj-text [lit] 0 cc-obj-r32 [lit] 0 [lit] 0 cc-obj-reloc", 246),
    ("open-failure", "create bad-path s, /no-such-object-writer-directory/file.o [lit] 0 c, bad-path cc-obj-write", 248),
    ("special-output", "create full-path s, /dev/full [lit] 0 c, full-path cc-obj-write", 248),
]
for name, body, status in bad:
    forth(name, "cc-obj-init\n" + body, status)

# Exact capacity and one-past capacity cases exercise the real input APIs.
# They do not write internal counters or fabricate malformed output records.
symbol_fill = f"""
cc-obj-init
variable fill-index
: fill-symbols
  [lit] 0 fill-index !
  begin, fill-index @ cc-obj-symbol-cap < while,
    {symbol} drop [lit] 1 fill-index +!
  repeat, ;
fill-symbols
"""
symbol_limit = write_object("symbol-limit", symbol_fill)
assert len(read_object(symbol_limit)[1]) == 2049
forth("symbol-one-past", symbol_fill + symbol, 245)
reloc_fill = f"""
cc-obj-init
{symbol} drop
[lit] 8 cc-obj-reserve drop
variable fill-index
: add-one cc-obj-text [lit] 0 cc-obj-r64 [lit] 1 [lit] 0 cc-obj-reloc ;
: fill-relocs
  [lit] 0 fill-index !
  begin, fill-index @ cc-obj-reloc-cap < while,
    add-one [lit] 1 fill-index +!
  repeat, ;
fill-relocs
"""
reloc_limit = write_object("reloc-limit", reloc_fill)
assert len(read_object(reloc_limit)[2]["text"]) == 4096
forth("reloc-one-past", reloc_fill + "add-one", 245)
name_fill = """
cc-obj-init
create long-name [lit] 65534 allot
: fill-name
  [lit] 0 begin, dup [lit] 65534 < while,
    [lit] 120 over long-name + c! 1+
  repeat, drop ;
fill-name
long-name [lit] 65534 cc-obj-global cc-obj-notype cc-obj-default cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol drop
"""
name_limit = write_object("name-limit", name_fill)
assert read_object(name_limit)[0][".strtab"][1][5] == 65536
forth("name-one-past", name_fill + symbol, 245)
section_limit = write_object("section-limit", """
cc-obj-init
cc-obj-section-cap cc-obj-reserve drop
cc-obj-rodata cc-obj-use cc-obj-section-cap cc-obj-reserve drop
cc-obj-data cc-obj-use cc-obj-section-cap cc-obj-reserve drop
cc-obj-bss cc-obj-use cc-obj-bss-cap cc-obj-reserve drop
""")
limit_sections = read_object(section_limit)[0]
for name in (".text", ".rodata", ".data"):
    assert limit_sections[name][1][5] == 131072
assert limit_sections[".bss"][1][5] == 1073741824
assert section_limit.stat().st_size < 400000

print(f"object-writer: cross-object executable exits 42; metadata/reset/capacities and {len(bad) + 6} rejection cases pass")
print(f"object-writer: inspectable evidence: {OUT}")
subprocess.run([sys.executable, ROOT / "tests/gcc/object-writer-publication-check.py"], check=True)
