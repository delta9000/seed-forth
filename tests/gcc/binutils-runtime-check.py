#!/usr/bin/env python3
"""Binutils runtime gate: file metadata, rewind, mktemp, wide and calendar
helpers (binutils-runtime-check.c) and correctly rounded atof
(decimal-input-check.c).

Forth-built programs and host GCC/glibc builds (-O0/-O2, independent oracles)
run serially under a one-GiB limit in fresh directories with TZ=UTC0 and must
print identical bytes, apart from lines marked runtime-only, which are checked
against this runtime's documented choice. atof results are also compared with
Python's correctly rounded float(); hexadecimal input is outside the contract
and is checked only against the documented 0.0 result. Host GCC lints the
changed runtime sources against the runtime headers alone.
"""
from decimal import Decimal, getcontext
from pathlib import Path
import hashlib
import json
import os
import random
import resource
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "runtime/gcc-seed"
METADATA = ROOT / "tests/gcc/binutils-runtime-check.c"
DECIMAL = ROOT / "tests/gcc/decimal-input-check.c"
LIMIT = 1024 ** 3
ENVIRONMENT = {"TZ": "UTC0", "PATH": "/usr/bin:/bin"}


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(command, data=None, **kwargs):
    command = [str(part) for part in command]
    result = subprocess.run(command, input=data, capture_output=True, timeout=600,
                            preexec_fn=limits, **kwargs)
    if result.returncode:
        raise SystemExit(f"{command}: exit {result.returncode}\n"
                         + result.stdout.decode(errors="replace")[-2000:]
                         + result.stderr.decode(errors="replace")[-2000:])
    return result.stdout


def metadata_run(executable, name):
    directory = work / ("run-" + name)
    (directory / "dir").mkdir(parents=True)
    (directory / "dir/inner").write_text("inner\n")
    (directory / "file").write_text("abc\n")
    os.symlink("file", directory / "link")
    output = run([executable], cwd=directory, env=ENVIRONMENT)
    left = sorted(str(p.relative_to(directory)) for p in directory.rglob("*"))
    if left != ["dir", "dir/inner", "file", "link"]:
        raise SystemExit(f"{name}: directory left as {left}")
    return output


def bits(text):
    """Python's float() is correctly rounded; return its binary64 bits."""
    return "%016x" % struct.unpack("<Q", struct.pack("<d", float(text)))[0]


def halfway(mantissa, exponent):
    """Exact decimal of (mantissa + 1/2) * 2^exponent."""
    getcontext().prec = 1300
    value = (Decimal(2 * mantissa + 1) / 2) * (Decimal(2) ** exponent)
    return format(value, "f") if abs(exponent) < 60 else format(value, "e")


def decimal_inputs():
    rng = random.Random(20261005)
    lines = ["0", "-0", "+0.000", "1", "-1", "0.1", "1e23", "8.98846567431158e307",
             "1.7976931348623157e308", "1.7976931348623158e308", "1.7976931348623159e308",
             "2.2250738585072011e-308", "2.2250738585072014e-308", "4.9406564584124654e-324",
             "2.4703282292062327e-324", "2.4703282292062328e-324", "1e-400", "-1e400",
             "9007199254740993", "9007199254740992.5", "  +12.5e+3x", "\t-.5", "5.", "e5",
             ".e5", "1e", "1e+", "-", "", "1" + "0" * 400, "0." + "0" * 400 + "1e400",
             "123456789012345678901234567890", "3.14159265358979323846264338327950288",
             "0.000001e6", "100e-2", "1e00000000000000000003", "1e-99999999999999"]
    # Exact half-way points rounded to even, and their nearest neighbours
    # expressed with digits far beyond the 800 kept by the runtime.
    for _ in range(120):
        exponent = rng.choice([rng.randint(-1126, -1060), rng.randint(-1080, 960),
                               rng.randint(960, 971)])
        mantissa = rng.randint(2 ** 52, 2 ** 53 - 1) if exponent > -1075 else rng.randint(0, 2 ** 20)
        exact = halfway(mantissa, exponent)
        lines.append(exact)
        mantissa_text, _, power = exact.partition("e")
        suffix = ("e" + power) if power else ""
        if "." not in mantissa_text:
            mantissa_text += "."
        lines.append(mantissa_text + "0" * 900 + "1" + suffix)
        lines.append(mantissa_text + "0" * 50 + "1" + suffix)
    for _ in range(4000):
        digits = "".join(rng.choice("0123456789") for _ in range(rng.choice([1, 5, 15, 17, 20, 40, 900])))
        text = rng.choice(["", "-", "+"]) + digits
        if rng.random() < 0.5:
            text += "." + "".join(rng.choice("0123456789") for _ in range(rng.randint(0, 25)))
        text += "e%d" % rng.randint(-1250, 330)
        lines.append(text)
    return lines


(ROOT / "build-out").mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix="binutils-runtime-", dir=ROOT / "build-out"))
for source, name in ((METADATA, "metadata"), (DECIMAL, "decimal")):
    run([sys.executable, ROOT / "tools/gcc-direct-cc.py", source, "-o", work / ("forth-" + name)])
    for optimization in ("-O0", "-O2"):
        run(["gcc", "-std=c99", "-pedantic", "-Wall", "-Wextra", "-Werror", optimization,
             "-fno-builtin", "-U_FORTIFY_SOURCE", "-D_GNU_SOURCE", source,
             "-o", work / ("host-" + name + optimization)])

actual = metadata_run(work / "forth-metadata", "forth")
if not actual.endswith(b"done\n"):
    raise SystemExit("Forth program did not complete:\n" + actual.decode(errors="replace"))
only = [line for line in actual.splitlines() if line.startswith(b"runtime-only ")]
if only != [b"runtime-only mbstowcs errno 84"] * 2:
    raise SystemExit(f"runtime-only lines: {only}")
compared = b"\n".join(line for line in actual.splitlines() if not line.startswith(b"runtime-only "))
for optimization in ("-O0", "-O2"):
    expected = metadata_run(work / ("host-metadata" + optimization), optimization[1:])
    expected = b"\n".join(line for line in expected.splitlines() if not line.startswith(b"runtime-only "))
    if compared != expected:
        for n, (a, e) in enumerate(zip(compared.splitlines(), expected.splitlines()), 1):
            if a != e:
                raise SystemExit(f"metadata line {n}: forth {a!r} != host {e!r}")
        raise SystemExit("metadata output lengths differ")

lines = decimal_inputs()
data = ("\n".join(lines) + "\n").encode()
decimal = run([work / "forth-decimal"], data, env=ENVIRONMENT).decode().split()
oracle = []
for text in lines:
    stripped = text.lstrip(" \t")
    body = stripped.lstrip("+-")
    end = 0
    while end < len(body) and (body[end].isdigit() or body[end] == "."):
        end += 1
    number = body[:end]
    if number.count(".") > 1 or not any(c.isdigit() for c in number):
        oracle.append(bits("-0.0" if False else "0.0"))
        continue
    rest = body[end:]
    if rest[:1] in ("e", "E"):
        k = 1 + (rest[1:2] in ("+", "-"))
        j = k
        while j < len(rest) and rest[j].isdigit():
            j += 1
        if j > k:
            number += rest[:j]
    oracle.append(bits(stripped[:len(stripped) - len(body)] + number))
for optimization in ("-O0", "-O2"):
    host = run([work / ("host-decimal" + optimization)], data, env=ENVIRONMENT).decode().split()
    if host != decimal:
        for text, a, e in zip(lines, decimal, host):
            if a != e:
                raise SystemExit(f"atof {text[:80]!r}: forth {a} != host{optimization} {e}")
        raise SystemExit("atof output lengths differ")
for text, a, e in zip(lines, decimal, oracle):
    if a != e:
        raise SystemExit(f"atof {text[:80]!r}: forth {a} != python {e}")
if len(decimal) != len(lines):
    raise SystemExit("atof output length differs from input")
hexadecimal = run([work / "forth-decimal"], b"0x10\n0x1p3\n").decode().split()
if hexadecimal != ["0000000000000000"] * 2:
    raise SystemExit(f"hexadecimal input: {hexadecimal}")

# Host stdarg.h replaces the runtime's (same ABI, Forth-specific spelling).
lint = work / "lint-include"
lint.mkdir()
compiler_include = run(["gcc", "-print-file-name=include"]).decode().strip()
(lint / "stdarg.h").write_text(f'#include "{compiler_include}/stdarg.h"\n')
LINT = ["gcc", "-std=c90", "-pedantic", "-fsyntax-only", "-nostdinc", "-isystem", lint,
        "-isystem", RUNTIME / "include", "-Wall", "-Wextra", "-Werror",
        "-Wno-builtin-declaration-mismatch", "-Wno-long-long"]
names = ["metadata.c", "mkstemp.c", "stdio.c", "wide.c", "calendar.c", "decimal.c", "scan.c"]
for name in names:
    run(LINT + [RUNTIME / name])
headers = ["sys/stat.h", "unistd.h", "utime.h", "stdio.h", "stdlib.h", "wctype.h", "time.h"]
sources = [METADATA, DECIMAL, Path(__file__)] + [RUNTIME / n for n in names] \
    + [RUNTIME / "include" / h for h in headers]
report = {"metadata_lines": actual.count(b"\n"), "decimal_inputs": len(lines),
          "host_oracles": ["-O0", "-O2"], "memory_limit_bytes": LIMIT, "environment": ENVIRONMENT,
          "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in sources},
          "forth_sha256": {name: hashlib.sha256((work / ("forth-" + name)).read_bytes()).hexdigest()
                           for name in ("metadata", "decimal")}}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: binutils runtime matches host glibc on {report['metadata_lines']} lines; "
      f"atof matches glibc and Python on {len(lines)} inputs", flush=True)
print(work / "report.json")
