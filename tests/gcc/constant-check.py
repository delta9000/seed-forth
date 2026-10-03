#!/usr/bin/env python3
"""Typed constants: Forth production evaluation, GCC as an independent oracle."""
from pathlib import Path
import random
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MASK = (1 << 64) - 1
INT, LONG, UCHAR, SHORT, USHORT, UINT, ULONG = 2, 6, 9, 5, 10, 11, 12

# Each golden records expression, unsigned 64-bit representation, base kind.
GOLDENS = [
    ("1", 1, INT), ("'A'", 65, INT), ("010", 8, INT),
    ("2147483648", 2147483648, LONG), ("0xffffffff", 0xffffffff, UINT),
    ("0x8000000000000000", 1 << 63, ULONG),
    ("4294967295U", 0xffffffff, UINT), ("4294967296U", 1 << 32, ULONG),
    ("1LL", 1, LONG), ("1ULL", 1, ULONG),
    ("0xffffffffU + 2U", 1, UINT), ("0U - 1", 0xffffffff, UINT),
    ("0xffffffffU * 2U", 0xfffffffe, UINT), ("~0U", 0xffffffff, UINT),
    ("-1U", 0xffffffff, UINT), ("(unsigned char)257", 1, UCHAR),
    ("(signed char)255", MASK, 1), ("(short)65535", MASK, SHORT),
    ("(unsigned short)-1", 65535, USHORT), ("+(unsigned short)65535", 65535, INT),
    ("(unsigned short)65535 + (signed char)255", 65534, INT),
    ("-1 < 1U", 0, INT), ("-1L < 1U", 1, INT),
    ("-1L < 1UL", 0, INT), ("1U + -2L", MASK, LONG),
    ("0x8000000000000000UL > 1", 1, INT),
    ("(-9223372036854775807L - 1) < 9223372036854775807L", 1, INT),
    ("9223372036854775807L > -1L", 1, INT),
    ("0xffffffffffffffffUL / 3UL", 6148914691236517205, ULONG),
    ("0xffffffffffffffffUL % 7UL", 1, ULONG),
    ("-7 / 3", (-2) & MASK, INT), ("-7 % 3", MASK, INT),
    ("7 / -3", (-2) & MASK, INT), ("7 % -3", 1, INT),
    ("0xffffffffU >> 31", 1, UINT), ("0x8000000000000000UL >> 63", 1, ULONG),
    ("-8 >> 2", (-2) & MASK, INT), ("1U << 31", 1 << 31, UINT),
    ("0xffffffffU << 4", 0xfffffff0, UINT), ("1UL << 63", 1 << 63, ULONG),
    ("1 << 30", 1 << 30, INT), ("0 << 31", 0, INT),
    ("2147483647 * 1", 2147483647, INT),
    ("(-2147483647-1) * 1", (-2147483648) & MASK, INT),
    ("(-9223372036854775807L-1) * 1L", 1 << 63, LONG),
    ("1 ? -1 : 1U", 0xffffffff, UINT), ("0 ? -1L : 1U", 1, LONG),
    ("0 ? (1/0) : 17", 17, INT), ("1 ? 23 : (1/0)", 23, INT),
    ("0 && (1/0)", 0, INT), ("1 || (1/0)", 1, INT),
    ("0 ? (1<<99) : 5", 5, INT),
    ("1 ? 2U : (0 ? 3L : (1/0))", 2, LONG),
    ("1 ? (0 ? 1/0 : 8) : 1/0", 8, INT),
    ("!2 + !!2", 1, INT), ("1 | 2 ^ 3 & 6", 1, INT),
    ("2 + 3 * 4 == 14 && 7 > 2", 1, INT),
    ("sizeof(int)", 4, ULONG), ("sizeof(long)", 8, ULONG),
    ("sizeof(float)", 4, ULONG), ("sizeof(double)", 8, ULONG),
    ("sizeof(long double)", 16, ULONG),
    ("sizeof(float*)", 8, ULONG), ("sizeof(double*)", 8, ULONG),
    ("sizeof(long double*)", 8, ULONG),
    ("sizeof(unsigned char)", 1, ULONG), ("sizeof(int[3])", 12, ULONG),
    ("sizeof(1U + 1UL)", 8, ULONG), ("sizeof(1 / 0)", 4, ULONG),
    ("sizeof(int[sizeof(char) + 2U])", 12, ULONG),
]

REJECTIONS = {
    "1 / 0": 124, "1 % 0": 124,
    "1 << -1": 241, "1U << 32": 241, "1UL >> 64": 241,
    "2147483647 + 1": 242, "(-2147483647-1) - 1": 242,
    "9223372036854775807L + 1L": 242,
    "(-9223372036854775807L-1) - 1L": 242,
    "2147483647 * 2": 242, "9223372036854775807L * 2L": 242,
    "(-2147483647-1) / -1": 242, "(-2147483647-1) % -1": 242,
    "-(-2147483647-1)": 242, "1 << 31": 242, "-1 << 1": 242,
    "(int *)0": 240, "unknown_name": 240, "&unknown_name": 240,
    "(double)1": 240,
    "1.5": 240, "1e3": 240, "0x1p4": 240, "09": 240,
    "18446744073709551616ULL": 240, "0x10000000000000000UL": 240,
    "1UU": 240, "1LUL": 240, "1lL": 240, "0xU": 240,
}


def layers():
    files = [ROOT / "010-lib.fth"] + [p for p in sorted(ROOT.glob("[0-9][0-9][0-9]-cc-*.fth"))
            if p.name not in ("120-cc-main.fth", "140-cc-link.fth")]
    return b"".join(p.read_bytes() for p in files)


def seed(source, count, api="cc-parse-integer-const", setup="cc-sysv-enable", declarations=0):
    declaration_parser = "cc-skip-storage-quals cc-next-token-keep true cc-native-declaration\n" * declarations
    driver = f"""
{setup}
[lit] 8388608 cc-arena-map
create const-output [lit] 16 allot
: const-check-main
  cc-load-stdin cc-preprocess cc-out-init cc-globals-init
  {declaration_parser}
  [lit] {count} begin, dup while,
    >r {api} const-output [lit] 8 + ! const-output !
    [char] ; cc-expect-punct-c
    cc-const-used @ if, [lit] 243 cc-die then,
    [lit] 1 const-output [lit] 16 write drop
    r> 1-
  repeat, drop
  cc-next-token-keep tok-kind @ tk-eof <> if, [lit] 244 cc-die then,
  bye ;
const-check-main
"""
    return subprocess.run([str(ROOT / "seed-forth")],
                          input=layers() + driver.encode() + source.encode(),
                          capture_output=True, timeout=30)


def main():
    expressions = [g[0] for g in GOLDENS]
    result = seed(";\n".join(expressions) + ";\n", len(expressions))
    if result.returncode or len(result.stdout) != 16 * len(expressions):
        raise AssertionError((result.returncode, result.stdout, result.stderr))
    observed = list(struct.iter_unpack("<QQ", result.stdout))
    for golden, actual in zip(GOLDENS, observed):
        expr, value, kind = golden
        assert actual == (value, kind << 16), (expr, actual, (value, kind << 16))
    print(f"PASS: {len(expressions)} golden constant values and types; pool restored")
    for expr, code in REJECTIONS.items():
        result = seed(expr + ";\n", 1)
        assert result.returncode == code, (expr, result.returncode, result.stdout, result.stderr)
    print(f"PASS: {len(REJECTIONS)} malformed or undefined constant operations rejected")
    for mode, expected in (("[lit] 0 cc-target-lp64 !", 4294967297),
                           ("true cc-target-lp64 !", 4294967297),
                           ("cc-sysv-enable", 1)):
        result = seed("0xffffffffU + 2U;\n", 1,
                      "cc-parse-const cc-const-int-type", mode)
        assert result.returncode == 0 and struct.unpack("<QQ", result.stdout)[0] == expected
    print("PASS: legacy/native constants retain original behavior; System V opts in")
    check_array_aliases()
    check_symbols()
    cc = shutil.which("gcc")
    if not cc:
        print("SKIP: optional GCC constant oracle is unavailable")
        return
    rng = random.Random(125)
    for _ in range(160):
        a, b, shift = rng.randrange(1 << 64), rng.randrange(1, 1 << 64), rng.randrange(64)
        expressions.extend([f"({a}UL / {b}UL)", f"({a}UL % {b}UL)",
                            f"({a}UL < {b}UL)", f"({a}UL >> {shift})",
                            f"((unsigned int){a}UL * (unsigned int){b}UL)"])
    actual = seed(";\n".join(expressions) + ";\n", len(expressions))
    assert actual.returncode == 0, (actual.returncode, actual.stderr)
    with tempfile.TemporaryDirectory(prefix="sf-constant-oracle.") as tmp:
        work = Path(tmp)
        code = '#include <stdio.h>\n#include <stdint.h>\n'
        code += '#define KIND(x) _Generic((x), char:1, signed char:1, unsigned char:9, short:5, unsigned short:10, int:2, unsigned int:11, long:6, unsigned long:12, long long:6, unsigned long long:12)\n'
        code += 'int main(void) { uint64_t item[2];\n'
        for expr in expressions:
            code += f'item[0]=(uint64_t)({expr}); item[1]=(uint64_t)KIND({expr})<<16; fwrite(item,8,2,stdout);\n'
        code += 'return 0; }\n'
        (work / "oracle.c").write_text(code)
        subprocess.run([cc, "-std=c11", "-w", "-O2", str(work / "oracle.c"), "-o", str(work / "oracle")], check=True)
        expected = subprocess.check_output([str(work / "oracle")])
        if actual.stdout != expected:
            got = list(struct.iter_unpack("<QQ", actual.stdout))
            want = list(struct.iter_unpack("<QQ", expected))
            failures = [(e, a, b) for e, a, b in zip(expressions, got, want) if a != b]
            raise AssertionError(failures[:12])
    print(f"PASS: {len(expressions)} constant values and types match independent GCC oracle")


def check_array_aliases():
    preamble = "typedef int A[3]; typedef A B; typedef A M[2];\n"
    expressions = "sizeof(A); sizeof(B); sizeof(M); sizeof(int); (int)1;\n"
    result = seed(preamble + expressions, 5, declarations=3)
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    assert list(struct.iter_unpack("<QQ", result.stdout)) == [
        (12, ULONG << 16), (12, ULONG << 16), (24, ULONG << 16),
        (4, ULONG << 16), (1, INT << 16),
    ]
    for expression in ("(A)1", "(B)1", "(M)1", "(A)(1/0)", "1 ? 1 : (A)1"):
        result = seed(preamble + expression + ";\n", 1, declarations=3)
        assert result.returncode == 240, (expression, result.returncode, result.stdout, result.stderr)
    print("PASS: array-alias sizeof retains full shape; array casts reject before operand evaluation")


def check_symbols():
    cases = [
        ("ints+3", (12, (INT << 16) + 1, 0, 17)),
        ("3+ints", (12, (INT << 16) + 1, 0, 17)),
        ("ints-2", ((-8) & MASK, (INT << 16) + 1, 0, 17)),
        ("(char*)ints+3", (3, (1 << 16) + 1, 0, 17)),
        ("(long)ints+3", (3, LONG << 16, 0, 17)),
        ("chars+2", (2, (1 << 16) + 1, 0, 23)),
        ("records+2", (24, (3 << 16) + 1, 9999, 31)),
        ("(void*)0", (0, 1, 0, 0)),
        ("1 ? ints : 0", (0, (INT << 16) + 1, 0, 17)),
        ("0 ? 0 : ints", (0, (INT << 16) + 1, 0, 17)),
        ("1 ? (unsigned long)ints : 0", (0, ULONG << 16, 0, 17)),
        ('1 ? chars : "dead"', (0, (1 << 16) + 1, 0, 23)),
        ('0 ? "dead" : chars', (0, (1 << 16) + 1, 0, 23)),
        ("functions", (0, (4 << 16) + 1, 7777, 37)),
        ("(unsigned long)functions", (0, ULONG << 16, 0, 37)),
        ('"live"+1', (1, (1 << 16) + 1, 0, 29)),
    ]
    setup = b"\ncc-sysv-enable\n[lit] 8388608 cc-arena-map\n"
    fixture = (ROOT / "tests/gcc/constant-symbols.fth").read_bytes()
    driver = f"""
: constant-symbol-main
  cc-load-stdin cc-preprocess cc-out-init cc-globals-init
  [lit] {len(cases)} begin, dup while,
    >r cc-parse-static-const constant-write [char] ; cc-expect-punct-c r> 1-
  repeat, drop
  constant-string-count @ [lit] 1 <> if, [lit] 245 cc-die then,
  cc-const-used @ if, [lit] 243 cc-die then, bye ;
constant-symbol-main
""".encode()
    source = (";\n".join(e for e, _ in cases) + ";\n").encode()
    result = subprocess.run([str(ROOT / "seed-forth")],
                            input=layers() + setup + fixture + driver + source,
                            capture_output=True, timeout=30)
    assert result.returncode == 0, (result.returncode, result.stderr)
    observed = list(struct.iter_unpack("<QQQQ", result.stdout))
    for (expr, expected), actual in zip(cases, observed):
        assert actual == expected, (expr, actual, expected)
    assert len(observed) == len(cases)
    reject_driver = b"\n: constant-reject cc-load-stdin cc-preprocess cc-out-init cc-globals-init cc-parse-static-const bye ;\nconstant-reject\n"
    for expr in ("ints*2", "(int)ints", "ints+chars", "2-ints", "ints==chars",
                 "functions+1", "(void*)ints+1", "ints && 1", "1 ? ints : chars"):
        result = subprocess.run([str(ROOT / "seed-forth")],
                                input=layers() + setup + fixture + reject_driver + (expr + ";\n").encode(),
                                capture_output=True, timeout=30)
        assert result.returncode == 240, (expr, result.returncode, result.stdout, result.stderr)
    for expr in ("(void*)functions", "(int)functions", "(int (*)(void))ints"):
        result = subprocess.run([str(ROOT / "seed-forth")],
                                input=layers() + setup + fixture + reject_driver + (expr + ";\n").encode(),
                                capture_output=True, timeout=30)
        assert result.returncode == 230, (expr, result.returncode, result.stdout, result.stderr)
    print(f"PASS: {len(cases)} symbolic constants; dead strings allocate nothing; unsupported relocations rejected")


if __name__ == "__main__":
    main()
