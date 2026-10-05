#!/usr/bin/env python3
"""LP64 atol: Forth production, Python integers, and separate host C90 oracles.

No unrepresentable input is ever passed to host libc atol. Target overflow is
an explicit saturation/ERANGE extension, checked against Python integers.
"""
from pathlib import Path
import hashlib
import json
import random
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
(ROOT / "build-out").mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix="atol-check-", dir=ROOT / "build-out"))
CC = [sys.executable, str(ROOT / "tools/gcc-direct-cc.py")]
MINIMUM = -(1 << 63)
MAXIMUM = (1 << 63) - 1
WHITESPACE = " \t\n\r\v\f"
cases = []


def expected(text):
    """Parse only ASCII decimal syntax using unbounded Python arithmetic."""
    remaining = text.lstrip(WHITESPACE)
    sign = 1
    if remaining[:1] in ("+", "-"):
        sign = -1 if remaining[0] == "-" else 1
        remaining = remaining[1:]
    digits = ""
    for char in remaining:
        if not "0" <= char <= "9":
            break
        digits += char
    value = sign * int(digits or "0")
    extension = not MINIMUM <= value <= MAXIMUM
    return max(MINIMUM, min(MAXIMUM, value)), extension


def add(text):
    value, extension = expected(text)
    cases.append((text, value, extension))


# Adjacent decimal cutoffs, values wider than int, and exact signed limits.
values = {MINIMUM, MINIMUM + 1, MAXIMUM - 1, MAXIMUM, 0, 1, -1,
          -(1 << 31) - 1, -(1 << 31), (1 << 31) - 1, 1 << 31,
          (1 << 32) - 1, 1 << 32, -(1 << 32), (1 << 53) + 1}
for exponent in range(1, 19):
    for offset in (-1, 0, 1):
        values.add(10 ** exponent + offset)
        values.add(-(10 ** exponent + offset))
for value in sorted(values):
    add(str(value))
    add(WHITESPACE + str(value) + "tail")
    if value >= 0:
        add("+000" + str(value) + "!")
    else:
        add("-000" + str(-value) + "!")
for whitespace in WHITESPACE:
    for suffix in ("", "+", "-", "+42!", "-42!", " 0"):
        add(whitespace + suffix)
for text in ("", "+", "-", "word", "++1", "+-1", "--1", "-+1",
             "+ 42", "-\t42", "0x123", "0b101", "010", "1.5", "1e9",
             "42-12", "-0", "+0", "\x8012", "\xa042", "\xff42",
             "42\x80", "\x0012", "12\x0034", "000" * 100 + "42"):
    add(text)
# Exercise every nonzero high byte and every ASCII control classification.
for byte in list(range(1, 33)) + list(range(127, 256)):
    add(chr(byte) + "17!")
    add("17" + chr(byte) + "23")
rng = random.Random(0xA701)
for unused in range(180):
    value = rng.randrange(MINIMUM, MAXIMUM + 1)
    add(rng.choice(("", " ", "\t\r\n")) + str(value) + rng.choice(("", "!", " rest")))
# Overflow is target-only. Values which fit unsigned long still overflow long.
for value in (MAXIMUM + 1, MAXIMUM + 2, MINIMUM - 1, MINIMUM - 2,
              1 << 64, (1 << 64) - 1, -(1 << 64), 10 ** 40):
    add(str(value))
    add(WHITESPACE + str(value) + "tail")
for text in ("9" * 4095, "-" + "9" * 4094, "0" * 4094 + "1",
             "0" * 4095, " " * 4095, " " * 4094 + "+"):
    add(text)


def quote(text):
    return '"' + "".join("\\%03o" % ord(char) for char in text) + '"'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


commands = []


def run(arguments):
    arguments = list(map(str, arguments))
    result = subprocess.run(arguments, capture_output=True, timeout=180)
    commands.append({"arguments": arguments, "returncode": result.returncode})
    if result.returncode or result.stderr:
        (OUT / "failed-stderr.txt").write_bytes(result.stderr)
        (OUT / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
        raise AssertionError((arguments, result.returncode, result.stdout[-1000:], result.stderr[-3000:]))
    return result.stdout


def check(executable, wanted):
    output = run([executable])
    (executable.parent / (executable.name + ".txt")).write_bytes(output)
    assert output == wanted, (executable, output[-1000:], wanted[-1000:])


identity = run(CC + ["--print-source-hash"]).decode().strip()
host = shutil.which("gcc")
assert host, "host GCC is required for the independent O0/O2 oracle checks"
host_flags = ["-std=c90", "-pedantic", "-Wall", "-Wextra", "-Werror",
              "-fno-builtin", "-D_GNU_SOURCE", "-DATOL_HOST", "-no-pie",
              "-Wl,-z,noexecstack"]
fixture = ROOT / "tests/gcc/atol-check.c"
runtime = ROOT / "runtime/gcc-seed/atol.c"
target_object = OUT / "forth-atol.o"
run(CC + ["-Datol=seed_atol", "-c", runtime, "-o", target_object])
host_objects = {}
for level in ("-O0", "-O2"):
    obj = OUT / ("host-atol" + level + ".o")
    run([host] + host_flags + [level, "-Datol=seed_atol", "-c", runtime, "-o", obj])
    host_objects[level] = obj

report = {"compiler_source_identity": identity, "cases": len(cases),
          "defined_cases": sum(not case[2] for case in cases),
          "extension_cases": sum(case[2] for case in cases),
          "errno_presets": [0, 33], "guard_edges_per_case": 2,
          "host_libc_overflow_calls": 0, "batches": []}
for start in range(0, len(cases), 100):
    part = cases[start:start + 100]
    directory = OUT / str(start)
    directory.mkdir()
    header = directory / "atol-cases.h"
    # Byte initializers keep full-page strings within C90's required string
    # literal limit; do not suppress any host warnings for the long cases.
    declarations = []
    rows = []
    for index, (text, value, extension) in enumerate(part):
        spelling = quote(text)
        if len(text) > 509:
            spelling = "long_text_" + str(index)
            declarations.append("static const char " + spelling + "[] = {" +
                                ",".join(str(ord(char)) for char in text) + ",0};\n")
        rows.append("{" + spelling + "," + str(int(extension)) + "},\n")
    header.write_text("".join(declarations) + "static struct test_case cases[] = {\n" +
                      "".join(rows) + "};\n")
    wanted = "".join(f"{i} {value} {34 if extension else error}\n"
                     for i, (text, value, extension) in enumerate(part)
                     for error in (0, 33)).encode()
    libc_wanted = "".join(f"{i} {value} {error}\n"
                          for i, (text, value, extension) in enumerate(part)
                          if not extension for error in (0, 33)).encode()
    (directory / "expected.txt").write_bytes(wanted)
    (directory / "libc-expected.txt").write_bytes(libc_wanted)
    production = directory / "forth-production"
    run(CC + ["-I", directory, fixture, "-o", production])
    check(production, wanted)
    # A static Forth-linked production ELF cannot import host libc.
    elf = production.read_bytes()
    assert elf[:5] == b"\x7fELF\x02"
    phoff = int.from_bytes(elf[32:40], "little")
    phsize = int.from_bytes(elf[54:56], "little")
    phcount = int.from_bytes(elf[56:58], "little")
    for index in range(phcount):
        ptype = int.from_bytes(elf[phoff + index * phsize:phoff + index * phsize + 4], "little")
        assert ptype not in (2, 3), "unexpected PT_DYNAMIC or PT_INTERP"
    for level in ("-O0", "-O2"):
        for name, extra, expectation in (
            ("libc", ["-DATOL_LIBC_ORACLE"], libc_wanted),
            ("host-source", ["-DATOL_INTEROP", host_objects[level]], wanted),
            ("forth-object", ["-DATOL_INTEROP", target_object], wanted),
        ):
            executable = directory / (name + level)
            run([host] + host_flags + [level, "-I", directory, fixture] + extra + ["-o", executable])
            check(executable, expectation)
    report["batches"].append({"start": start, "count": len(part),
                              "production_sha256": sha(production),
                              "fixture_header_sha256": sha(header),
                              "expected_sha256": hashlib.sha256(wanted).hexdigest()})

assert identity == run(CC + ["--print-source-hash"]).decode().strip(), "compiler changed during checks"
report["source_sha256"] = {str(path.relative_to(ROOT)): sha(path) for path in (
    runtime, ROOT / "runtime/gcc-seed/include/stdlib.h", fixture, Path(__file__))}
report["forth_atol_object_sha256"] = sha(target_object)
report["passed"] = {"forth_production": True, "host_libc_O0_O2_defined_only": True,
                    "host_source_O0_O2": True, "forth_object_host_O0_O2": True}
(OUT / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
(OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print("PASS:", len(cases), "atol cases; Forth-only, host libc defined inputs O0/O2,")
print("host-compiled implementation O0/O2, Forth-object/host interoperability, both guard edges")
print(OUT / "report.json")
