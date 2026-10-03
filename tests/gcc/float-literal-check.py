#!/usr/bin/env python3
"""Source Forth binary64 decoder against an independent exact-rational oracle.

Python transports source and observes cells. Only the oracle uses Python
integers/Fraction; no oracle value or host floating parser enters production.
The deterministic corpus and source hashes make each run replayable.
"""
from fractions import Fraction
import argparse
import hashlib
import json
from pathlib import Path
import random
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ["000-seed.hex0", "010-lib.fth", "020-cc-arena.fth",
           "030-cc-io.fth", "128-cc-float-literal.fth",
           "book/46-direct-gcc-float-literals.md", "tests/gcc/float-literal-check.py"]
GRAMMAR = re.compile(r"(?:[0-9]+\.[0-9]*|\.[0-9]+|[0-9]+)(?:[eE][+-]?[0-9]+)?\Z")
MAX_BITS = 0x7FEFFFFFFFFFFFFF


def sha(data):
    return hashlib.sha256(data).hexdigest()


def exact_value(token):
    assert GRAMMAR.fullmatch(token) and any(c in token for c in ".eE"), token
    mantissa, *power = re.split("[eE]", token)
    exponent = int(power[0]) if power else 0
    fractional = len(mantissa.split(".")[1]) if "." in mantissa else 0
    digits = mantissa.replace(".", "").lstrip("0")
    if not digits:
        return Fraction(0)
    exponent -= fractional
    order = len(digits) + exponent - 1
    if order > 308:
        raise OverflowError(token)
    if order < -324:
        return Fraction(0)
    coefficient = int(digits)
    return (Fraction(coefficient * 10 ** exponent) if exponent >= 0 else
            Fraction(coefficient, 10 ** -exponent))


def round_even(numerator, denominator):
    quotient, remainder = divmod(numerator, denominator)
    if 2 * remainder > denominator or (2 * remainder == denominator and quotient % 2):
        quotient += 1
    return quotient


def oracle(token):
    value = exact_value(token)
    if not value:
        return 0
    n, d = value.numerator, value.denominator
    exponent = n.bit_length() - d.bit_length()
    if (n < d << exponent) if exponent >= 0 else (n << -exponent < d):
        exponent -= 1
    if exponent < -1022:
        return round_even(n << 1074, d)
    shift = 52 - exponent
    mantissa = round_even(n << shift, d) if shift >= 0 else round_even(n, d << -shift)
    if mantissa == 1 << 53:
        mantissa >>= 1
        exponent += 1
    if exponent > 1023:
        raise OverflowError(token)
    return ((exponent + 1023) << 52) + mantissa - (1 << 52)


def bits_fraction(bits):
    exponent, mantissa = bits >> 52, bits & ((1 << 52) - 1)
    if exponent:
        mantissa += 1 << 52
        shift = exponent - 1075
    else:
        shift = -1074
    return (Fraction(mantissa << shift) if shift >= 0 else
            Fraction(mantissa, 1 << -shift))


def dyadic_decimal(value):
    """Exact decimal spelling of a nonnegative fraction with power-of-two denominator."""
    exponent = value.denominator.bit_length() - 1
    assert value.denominator == 1 << exponent
    return str(value.numerator * 5 ** exponent) + "e-" + str(exponent)


def corpus():
    valid = [
        "0.0", ".0", "0.", "0e0", "00.000", ".5", "1.", "1e3", "1E+3",
        "00001.2300e-2", "0.1", "0.2", "0.3", "2.5", "2.2250738585072014e-308",
        "2.2250738585072011e-308", "1.7976931348623157e308", "1.7976931348623158e308",
        "4.9406564584124654e-324", "5e-324", "4e-324", "3e-324", "2e-324", "1e-324",
        "1e-325", "1e-1000000", "0e1000000", "0e-1000000", "1.0e00000000000000003",
        "9007199254740991.0", "9007199254740992.0", "9007199254740993.0",
        "9007199254740995.0", "18446744073709551615.0",
        "1" + "0" * 767 + "e-767", "9" * 768 + "e-768",
        "1" + "0" * 767 + "e-1091", "9" * 768 + "e-460",
        "0" * 4094 + ".1", "." + "0" * 4095,
    ]
    # Midpoint equality tests both odd and even endpoints; perturbing the
    # least decimal place tests decisions that a fixed prefix would lose.
    adjacent_lower = [0, 1, 2, 3, 0xFFFFFFFFFFFFE, 0xFFFFFFFFFFFFF,
                      0x10000000000000, 0x10000000000001,
                      0x3FDFFFFFFFFFFFFF, 0x3FE0000000000000,
                      0x3FEFFFFFFFFFFFFF, 0x3FF0000000000000,
                      0x3FF0000000000001, 0x3FF0000000000002,
                      0x433FFFFFFFFFFFFF, 0x4340000000000000, MAX_BITS - 1]
    for lower in adjacent_lower:
        midpoint = (bits_fraction(lower) + bits_fraction(lower + 1)) / 2
        spelling = dyadic_decimal(midpoint)
        coefficient, exponent = spelling.split("e")
        valid.extend(str(int(coefficient) + delta) + "e" + exponent for delta in (-1, 0, 1))
    overflow_midpoint = (bits_fraction(MAX_BITS) + Fraction(1 << 1024)) / 2
    valid.append(dyadic_decimal(overflow_midpoint - 1))
    # Fixed seed and finite size, including large significands near the
    # workspace bound and exponents on both sides of every range gate.
    rng = random.Random(0xF64DEC)
    for length in [1, 2, 15, 16, 17, 18, 53, 100, 300, 767, 768]:
        for _ in range(12):
            digits = str(rng.randrange(1, 10)) + "".join(str(rng.randrange(10)) for _ in range(length - 1))
            order = rng.choice([-325, -324, -323, -309, -308, -307, -1, 0, 1, 307, 308])
            token = digits + "e" + str(order - length + 1)
            try:
                oracle(token)
            except OverflowError:
                continue
            valid.append(token)
    # Repeated state resets include zero after a huge ratio and large after tiny.
    valid += ["1e-324", "0.0", "1e308", ".5", "0e1000000", "1e-308"] * 3
    invalid = {token: "malformed" for token in [
        "", ".", "1", "123", "e3", ".e3", "1e", "1e+", "1e-", "1e++2", "1e+-2",
        "1.2.3", "1..", "1e2e3", "1e2.3", "1.0x", "1.0_", "1.0 ", " 1.0",
        "+1.0", "-1.0", "nan", "inf", "Infinity", "1p0", "1.0U", "1.0\x00x",
    ]}
    invalid.update({token: "suffix-unsupported" for token in [
        "1.0f", "1.0F", ".5l", "1.L", "1e3f", "1f", "1L", "1.0ff",
    ]})
    invalid.update({token: "hexfloat-unsupported" for token in [
        "0x1p0", "0X1.Ap+2", "0x.1p0", "0x0p0", "0x1.0", "0x",
    ]})
    invalid.update({
        "1" + "0" * 768 + "e-768": "digit-limit",
        "0." + "0" * 4095: "token-limit",
        "1e1000001": "exponent-limit", "1e-1000001": "exponent-limit",
        "0e1000001": "exponent-limit", "0e999999999999999999999": "exponent-limit",
        "1e309": "overflow", "1e1000000": "overflow", "1.7976931348623159e308": "overflow",
        dyadic_decimal(overflow_midpoint): "overflow",
        dyadic_decimal(overflow_midpoint + 1): "overflow",
    })
    return valid, invalid


def layers():
    return (b"".join((ROOT / p).read_bytes() for p in SOURCES[1:4]) +
            b"\ndefer cc-f64-parse-fwd\n" + (ROOT / SOURCES[4]).read_bytes())


DRIVER = b"""
create float-output [lit] 8 allot
variable float-start
variable float-cursor
: float-main
  cc-load-stdin cc-in-buf dup float-start ! float-cursor !
  [lit] 123456789
  begin, float-cursor @ cc-in-buf cc-in-len @ + < while,
    float-cursor @ c@ nl = if,
      float-start @ float-cursor @ over - cc-f64-parse float-output !
      [lit] 1 float-output [lit] 8 write drop
      float-cursor @ 1+ float-start !
    then,
    [lit] 1 float-cursor +!
  repeat,
  [lit] 123456789 <> if, [lit] 247 die then,
  [lit] 0 die ;
float-main
"""


def run(source_layers, tokens):
    return subprocess.run([str(ROOT / "seed-forth")],
                          input=source_layers + DRIVER + ("\n".join(tokens) + "\n").encode(),
                          capture_output=True, timeout=60)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    # Verify the running seed is the checked-in hex0 source, never a host build.
    hex0 = "".join(line.split(";")[0].split("#")[0] for line in (ROOT / SOURCES[0]).read_text().splitlines())
    assert bytes.fromhex(hex0) == (ROOT / "seed-forth").read_bytes(), "seed/source mismatch"
    hashes = {p: sha((ROOT / p).read_bytes()) for p in SOURCES}
    valid, invalid = corpus()
    source_layers = layers()
    first = run(source_layers, valid)
    assert first.returncode == 0, (first.returncode, first.stderr.decode())
    assert len(first.stdout) == 8 * len(valid), (len(first.stdout), len(valid))
    for token, (observed,) in zip(valid, struct.iter_unpack("<Q", first.stdout)):
        expected = oracle(token)
        assert observed == expected, (token, hex(observed), hex(expected))
    # Replay byte-for-byte and with reverse order to detect retained parser state.
    replay = run(source_layers, valid)
    assert (replay.returncode, replay.stdout, replay.stderr) == (0, first.stdout, b"")
    reverse = run(source_layers, list(reversed(valid)))
    assert reverse.returncode == 0 and reverse.stdout == b"".join(
        struct.pack("<Q", oracle(token)) for token in reversed(valid)), reverse.stderr
    for token, reason in invalid.items():
        result = run(source_layers, [token])
        assert result.returncode == 248 and not result.stdout, (token, result.returncode, result.stdout)
        assert result.stderr == ("cc-f64-literal: " + reason + "\n").encode(), (token, result.stderr, reason)
    assert hashes == {p: sha((ROOT / p).read_bytes()) for p in SOURCES}, "sources changed during run"
    report = {
        "schema": 1, "production": "seed Forth integer-ratio decoder",
        "oracle": "Python Fraction and integer divmod; no host floating conversion",
        "bounds": {"token_bytes": 4096, "significant_digits": 768,
                   "absolute_decimal_exponent": 1000000, "workspace_bits": 4096},
        "valid_cases": len(valid), "rejected_cases": len(invalid),
        "replay": "same order byte-identical; reverse order independently checked",
        "seed_sha256": sha((ROOT / "seed-forth").read_bytes()), "source_sha256": hashes,
        "corpus_sha256": sha(json.dumps([valid, invalid], sort_keys=True).encode()),
        "binary64_output_sha256": sha(first.stdout),
    }
    if args.report:
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"PASS: {len(valid)} exact binary64 values; {len(invalid)} precise rejections; two deterministic replays")


if __name__ == "__main__":
    main()
