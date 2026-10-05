#!/usr/bin/env python3
"""Exercise Forth LP64 metadata and machine encoders without the C parser.

Python is only the test runner: seed-forth creates every instruction under test.
Generated routines run from a private anonymous mapping; no shared /tmp/cc-out
or host compiler is involved.
"""
import ctypes
import mmap
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
MASK = (1 << 64) - 1
BASES = ["void", "char", "int", "struct", "func", "short", "long",
         "float", "double", "uchar", "ushort", "uint", "ulong", "ldouble"]
LAYERS = ["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth",
          "050-cc-lex.fth", "060-cc-types.fth", "080-cc-elf.fth", "090-cc-emit.fth"]
VOCAB = "\n".join((ROOT / name).read_text() for name in LAYERS)
HELPERS = """
create test-cell [lit] 8 allot
: test-result test-cell ! [lit] 1 test-cell [lit] 8 write drop ;
: test-code cc-out-pos @ test-result
  [lit] 1 cc-out-buf cc-out-pos @ write drop ;
"""


def run_forth(source, input_text=None):
    result = subprocess.run([str(ROOT / "seed-forth")],
                            input=(VOCAB + HELPERS + source + ("\nbye\n" if input_text is None else "\n" + input_text)).encode(),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            cwd=ROOT, timeout=20)
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    return result.stdout


def ty(name):
    return "ty-" + name + " [lit] 0 ty-make"


def raw(*values):
    return " ".join(f"[lit] {v} cc-emit-byte" for v in values)


# Complete type matrix, pointer behavior and default-mode compatibility.
source = "cc-target-lp64 @ test-result\n"
expected = [0]
for mode in (0, 1):
    source += f"[lit] {mode} cc-target-lp64 !\n"
    sizes = ([0, 1] + [8] * 12 if not mode else
             [0, 1, 4, 8, 8, 2, 8, 4, 8, 1, 2, 4, 8, 16])
    for base, size in zip(BASES, sizes):
        source += f"{ty(base)} ty-size test-result\n"
        source += f"{ty(base)} ty-align test-result\n"
        source += f"{ty(base)} ty-unsigned? test-result\n"
        source += f"ty-{base} [lit] 1 ty-make ty-size test-result\n"
        source += f"ty-{base} [lit] 2 ty-make ty-unsigned? test-result\n"
        unsigned = base in ("uchar", "ushort", "uint", "ulong") or (not mode and base == "char")
        expected += [size, size or 1, MASK if unsigned else 0, 8, MASK]
source += """
cc-bootstrap-floatbits @ test-result
[lit] 1 cc-bootstrap-floatbits !
ty-float [lit] 0 ty-make ty-size test-result
ty-double [lit] 0 ty-make ty-size test-result
ty-ldouble [lit] 0 ty-make ty-align test-result
[lit] 0 cc-bootstrap-floatbits !
[lit] 0 cc-target-lp64 ! cc-sd-header-bytes test-result
[lit] 1 cc-target-lp64 ! cc-sd-header-bytes test-result
variable test-desc
cc-arena-ptr @ dup [lit] 99 swap ! [lit] 99 over [lit] 56 + c!
cc-sd-alloc dup test-desc ! swap = test-result
 test-desc @ cc-sd-total-size test-result
 test-desc @ [lit] 56 + c@ test-result
 test-desc @ cc-sd-table test-result
 test-desc @ cc-sd-table-cap test-result
[lit] 16 test-desc @ cc-sd-set-align
 test-desc @ cc-sd-align test-result
[lit] 1 test-desc @ cc-sd-set-union
 test-desc @ cc-sd-union? test-result
\\ Append 12 fields: the first touches an 8-record table at the arena top,
\\ the ninth moves the records into a 16-record table.
: test-fields
  [lit] 0 begin, dup [lit] 12 < while,
    dup [lit] 100 + over test-desc @ swap cc-sd-field-rec cc-sf-set-array-len
    dup 1+ test-desc @ cc-sd-set-field-count
    dup [lit] 0 = if, test-desc @ cc-sd-table test-desc @ - test-result then,
    1+
  repeat, drop ;
test-fields
 test-desc @ cc-sd-table-cap test-result
 test-desc @ cc-sd-table test-desc @ - test-result
 test-desc @ [lit] 3 cc-sd-field-rec cc-sf-array-len test-result
 test-desc @ [lit] 11 cc-sd-field-rec cc-sf-array-len test-result
 test-desc @ [lit] 11 cc-sd-field-rec test-desc @ [lit] 10 cc-sd-field-rec - test-result
 test-desc @ [lit] 0 cc-sd-field-rec test-desc @ cc-sd-table - test-result
 test-desc @ cc-sd-field-count test-result
 test-desc @ cc-sd-align test-result
 test-desc @ cc-sd-union? test-result
"""
# Fixed 56-byte header for both settings; allocation stops at its canary;
# the first table follows the header; growth doubles to 16 records after
# the abandoned 8 x 48-byte table, copying records contiguously.
expected += [0, 8, 8, 8, 56, 56, MASK, 0, 99, 0, 0, 16, 1, 56,
             16, 56 + 8 * 48, 103, 111, 48, 0, 12, 16, 1]
result = run_forth(source)
assert len(result) == len(expected) * 8, result
actual = list(struct.unpack("<" + "Q" * len(expected), result))
assert actual == expected, [(i, a, b) for i, (a, b) in enumerate(zip(actual, expected)) if a != b]

# Numeric spelling and LP64 suffix/base classification survive lexer marks.
numbers = [
    ("0", 0, 2), ("1", 1, 2), ("2147483647", (1 << 31) - 1, 2),
    ("2147483648", 1 << 31, 6), ("4294967295", (1 << 32) - 1, 6),
    ("9223372036854775807", (1 << 63) - 1, 6),
    ("9223372036854775808", 1 << 63, 12), (str(MASK), MASK, 12),
    ("0x7fffffff", (1 << 31) - 1, 2), ("0X80000000", 1 << 31, 11),
    ("0xffffffff", (1 << 32) - 1, 11), ("0x100000000", 1 << 32, 6),
    ("0x7fffffffffffffff", (1 << 63) - 1, 6),
    ("0x8000000000000000", 1 << 63, 12), ("0xffffffffffffffff", MASK, 12),
    ("020000000000", 1 << 31, 11), ("037777777777", (1 << 32) - 1, 11),
    ("1u", 1, 11), ("1U", 1, 11), ("1ul", 1, 12), ("1lu", 1, 12),
    ("1Ull", 1, 16), ("1LLU", 1, 16), ("1L", 1, 6), ("1LL", 1, 15),
    ("9223372036854775807LL", (1 << 63) - 1, 15),
    ("0x8000000000000000ll", 1 << 63, 16),
    ("2147483648L", 1 << 31, 6), ("0xffffffffL", (1 << 32) - 1, 6),
    ("4294967296u", 1 << 32, 12), ("0xffffffffffffffffu", MASK, 12),
]
for mode in (0, 1):
    source = f"[lit] {mode} cc-target-lp64 !\n" + r"""
: test-number
  cc-next-token
  tok-kind @ tk-num <> if, [lit] 240 cc-die then,
  tok-num @ test-result cc-integer-literal-type ty-base test-result
  tok-str-len @ test-result
  [lit] 1 tok-str-addr @ tok-str-len @ write drop
  cc-peek-mark cc-lex-mark cc-next-token cc-peek-mark cc-lex-reset
  cc-integer-literal-type ty-base test-result ;
: test-numbers
  cc-src-init [lit] 0 cc-src-buf cc-src-cap [lit] 20 cc-read-all cc-src-len !
""" + f"[lit] {len(numbers)}" + r"""
  begin, dup while, test-number 1- repeat, drop bye ;
test-numbers
"""
    data = run_forth(source, " ".join(n[0] for n in numbers) + "\n")
    for spelling, value, base in numbers:
        actual_value, actual_base, length = struct.unpack("<QQQ", data[:24])
        actual_spelling, data = data[24:24 + length], data[24 + length:]
        restored_base, = struct.unpack("<Q", data[:8])
        data = data[8:]
        assert actual_value == value, spelling
        assert actual_base == restored_base == (base if mode else 2), spelling
        assert actual_spelling.decode() == spelling, spelling
    assert not data

# Compile all routines once, framing each private result with its byte length.
fragments = {}
integer_types = ["char", "uchar", "short", "ushort", "int", "uint", "long", "ulong"]
for base in integer_types:
    fragments["load_" + base] = f"{ty(base)} cc-emit-load-typed-via-rdi"
    fragments["store_" + base] = raw(72, 137, 241) + f" {ty(base)} cc-emit-store-typed-via-rcx"
    fragments["convert_" + base] = f"{ty(base)} cc-emit-convert-rdi"
    fragments["right_" + base] = "cc-emit-mov-rcx-rdi " + f"{ty(base)} cc-emit-convert-rcx " + raw(72, 137, 207)
    for slot in (0, 16):
        fragments[f"local_{base}_{slot}"] = (f"[lit] 256 cc-emit-prologue [lit] {slot} {ty(base)} cc-emit-store-local-typed "
            f"[lit] {slot} {ty(base)} cc-emit-load-local-typed cc-emit-mov-rax-rdi cc-emit-epilogue")
for opname in ("udiv-quotient", "udiv-remainder", "cmp-ult", "cmp-ule", "cmp-ugt", "cmp-uge", "shr-rdi-cl"):
    fragments[opname] = raw(72, 137, 241) + " cc-emit-" + opname
for value in (0, (1 << 31) - 1, 1 << 31, 1 << 63, MASK):
    fragments[f"imm_{value}"] = f"[lit] {value} cc-emit-mov-rdi-int"
fragments["legacy_load_char"] = "[lit] 0 cc-target-lp64 ! " + ty("char") + " cc-emit-load-typed-via-rdi"
fragments["legacy_load_int"] = "[lit] 0 cc-target-lp64 ! " + ty("int") + " cc-emit-load-typed-via-rdi"
fragments["legacy_local_char"] = "[lit] 0 cc-target-lp64 ! [lit] 0 " + ty("char") + " cc-emit-load-local-typed"
program = ""
for name, body in fragments.items():
    program += "[lit] 1 cc-target-lp64 ! cc-out-init " + body
    if not name.startswith("local_"):
        program += " cc-emit-mov-rax-rdi " + raw(195)
    program += " test-code\n"
data = run_forth(program)
code = {}
for name in fragments:
    length, = struct.unpack("<Q", data[:8])
    code[name], data = data[8:8 + length], data[8 + length:]
assert not data


def invoke(name, *args):
    with mmap.mmap(-1, len(code[name]), prot=mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC) as mem:
        mem.write(code[name])
        addr = ctypes.addressof(ctypes.c_char.from_buffer(mem))
        function = ctypes.CFUNCTYPE(ctypes.c_uint64, *([ctypes.c_uint64] * len(args)))(addr)
        return function(*args)


widths = {"char": 1, "uchar": 1, "short": 2, "ushort": 2, "int": 4, "uint": 4, "long": 8, "ulong": 8}
for base in integer_types:
    width = widths[base]
    for value in (0, 1, (1 << (width * 8 - 1)) - 1, 1 << (width * 8 - 1), MASK, 0x98765432876543AB):
        value &= MASK
        truncated = value & ((1 << (width * 8)) - 1)
        signed = not base.startswith("u")
        normalized = truncated
        if signed and truncated & (1 << (width * 8 - 1)):
            normalized |= MASK ^ ((1 << (width * 8)) - 1)
        for prefix in ("convert_", "right_", "local_"):
            names = [prefix + base] if prefix != "local_" else [f"local_{base}_0", f"local_{base}_16"]
            for name in names:
                assert invoke(name, value) == normalized, (name, hex(value))
        buffer = (ctypes.c_ubyte * 16).from_buffer_copy(struct.pack("<QQ", value, MASK))
        assert invoke("load_" + base, ctypes.addressof(buffer)) == normalized, ("load", base, hex(value))
        buffer = (ctypes.c_ubyte * 16)(*([0xA5] * 16))
        assert invoke("store_" + base, value, ctypes.addressof(buffer)) == value
        assert bytes(buffer) == value.to_bytes(8, "little")[:width] + b"\xa5" * (16 - width)

for a, b in ((0, 1), (1, 2), (MASK, 3), (1 << 63, 3), (MASK, MASK), (42, 42)):
    assert invoke("udiv-quotient", a, b) == a // b
    assert invoke("udiv-remainder", a, b) == a % b
    for op, result in (("ult", a < b), ("ule", a <= b), ("ugt", a > b), ("uge", a >= b)):
        assert invoke("cmp-" + op, a, b) == result
for shift in (0, 1, 31, 32, 63):
    assert invoke("shr-rdi-cl", MASK, shift) == MASK >> shift
for value in (0, (1 << 31) - 1, 1 << 31, 1 << 63, MASK):
    assert invoke(f"imm_{value}") == value
assert code["legacy_load_char"].hex() == "480fb63f4889f8c3"
assert code["legacy_load_int"].hex() == "488b3f4889f8c3"
assert code["legacy_local_char"].hex() == "488b7df84889f8c3"
print("PASS: LP64 type/literal matrices, lexer marks, descriptor clearing, typed memory/conversions/locals, unsigned ALU, full-width literals, legacy bytes")
