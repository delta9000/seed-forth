#!/usr/bin/env python3
"""Derive every binary64 table in runtime/gcc-seed/math.c from first principles,
and check that each math.h M_* literal is the binary64 nearest its value.

Original seed-forth tool, MIT license. Uses only Python integers, Fraction
and Decimal (no libm, no third-party library). pi is computed with Machin's
formula in integer fixed point; logarithms, exponentials and arctangents use
Decimal at two independent precisions, and both precisions must agree on
every emitted bit. Each double-double entry is hi = RN(v), lo = RN(v - hi).

  python3 tests/gcc/math-constants.py           # verify math.c block and M_*
  python3 tests/gcc/math-constants.py --print   # print the generated block
"""
from decimal import Decimal, getcontext, localcontext
from fractions import Fraction
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'runtime/gcc-seed/math.c'
BEGIN = '/* BEGIN GENERATED TABLES (tests/gcc/math-constants.py) */\n'
END = '/* END GENERATED TABLES */\n'
TWO_OVER_PI_WORDS = 40


def bits(x):
    return struct.unpack('<Q', struct.pack('<d', x))[0]


def rn(value):
    """Round a Fraction to the nearest binary64, ties to even (normal range)."""
    return float(value)  # Fraction.__float__ is correctly rounded


def machin_pi(nbits):
    """floor(pi * 2^nbits) - small, via 16 atan(1/5) - 4 atan(1/239)."""
    guard = 64
    scale = 1 << (nbits + guard)

    def arctan_inv(n):
        total = 0
        term = scale // n
        k = 0
        n2 = n * n
        while term:
            if k % 2 == 0:
                total += term // (2 * k + 1)
            else:
                total -= term // (2 * k + 1)
            term //= n2
            k += 1
        return total
    return (16 * arctan_inv(5) - 4 * arctan_inv(239)) >> guard


def pi_fraction(nbits):
    return Fraction(machin_pi(nbits), 1 << nbits)


def dec_atan(x):
    """Decimal arctangent by three argument halvings and the Taylor series."""
    halvings = 0
    one = Decimal(1)
    while x > Decimal('0.125'):
        x = x / (one + (one + x * x).sqrt())
        halvings += 1
    total = Decimal(0)
    power = x
    k = 0
    eps = Decimal(10) ** (-(getcontext().prec + 5))
    while abs(power) > eps:
        total += power / (2 * k + 1) if k % 2 == 0 else -power / (2 * k + 1)
        power *= x * x
        k += 1
    return total * (2 ** halvings)


def dd(value):
    """value: Fraction or Decimal -> (hi, lo) binary64 pair."""
    if isinstance(value, Decimal):
        value = Fraction(value)
    hi = rn(value)
    lo = rn(value - Fraction(hi))
    return hi, lo


def derive(prec):
    with localcontext() as ctx:
        ctx.prec = prec
        d2 = Decimal(2)
        ln2 = d2.ln()
        ln10 = Decimal(10).ln()
        pi = Fraction(machin_pi(prec * 4))  # integer, scaled below
        pi = pi / (1 << (prec * 4))
        out = {}
        out['LN2'] = dd(ln2)
        out['INVLN2'] = dd(1 / ln2)
        out['INVLN10'] = dd(1 / ln10)
        out['PIO2'] = dd(pi / 2)
        out['PI'] = dd(pi)
        out['THREEPIO4'] = dd(3 * pi / 4)
        out['S3'] = dd(Fraction(-1, 6))
        out['S5'] = dd(Fraction(1, 120))
        out['C4'] = dd(Fraction(1, 24))
        out['C6'] = dd(Fraction(-1, 720))
        # log(i/128), i = 96..192
        out['LOGC'] = [dd((Decimal(i) / 128).ln()) for i in range(96, 193)]
        # 2^(j/64), j = 0..63
        out['EXP2T'] = [dd((Decimal(j) / 64 * ln2).exp()) for j in range(64)]
        # atan(i/32), i = 0..32
        out['ATANT'] = [dd(dec_atan(Decimal(i) / 32)) for i in range(33)]
        # Cody-Waite pi/2: three 33-bit leading pieces and a rounded tail.
        rest = pi / 2
        pieces = []
        for _ in range(3):
            # truncate rest to 33 significant bits
            e = 0
            while Fraction(1 << 32, 1) * Fraction(2) ** e > rest:
                e -= 1
            while Fraction(1 << 33, 1) * Fraction(2) ** e <= rest:
                e += 1
            # now 2^32 <= rest/2^e < 2^33
            m = int(rest / Fraction(2) ** e)
            piece = Fraction(m) * Fraction(2) ** e
            pieces.append(float(piece))
            assert Fraction(pieces[-1]) == piece
            rest -= piece
        pieces.append(rn(rest))
        out['CW'] = pieces
        return out


def two_over_pi_words(count):
    nbits = 32 * count + 128
    pi_fixed = machin_pi(nbits + 64)          # pi * 2^(nbits+64)
    q = (1 << (2 * nbits + 65)) // pi_fixed   # floor(2/pi * 2^nbits) (+-1)
    words = [(q >> (nbits - 32 * (j + 1))) & 0xffffffff for j in range(count)]
    return words


def emit():
    first = derive(80)
    second = derive(120)
    assert first == second, 'Decimal precisions disagree'
    words = two_over_pi_words(TWO_OVER_PI_WORDS)
    assert words == two_over_pi_words(TWO_OVER_PI_WORDS + 8)[:TWO_OVER_PI_WORDS]
    lines = [BEGIN]

    def scalar(name, pair):
        hi, lo = pair
        lines.append('#define SEED_%s_H 0x%016xUL /* %r */\n' % (name, bits(hi), hi))
        lines.append('#define SEED_%s_L 0x%016xUL /* %r */\n' % (name, bits(lo), lo))
    for name in ['LN2', 'INVLN2', 'INVLN10', 'PIO2', 'PI', 'THREEPIO4',
                 'S3', 'S5', 'C4', 'C6']:
        scalar(name, first[name])
    for index, value in enumerate(first['CW']):
        lines.append('#define SEED_PIO2_CW%d 0x%016xUL /* %r */\n' % (index + 1, bits(value), value))

    def table(name, comment, pairs):
        lines.append('/* %s */\n' % comment)
        lines.append('static const unsigned long %s[%d] = {\n' % (name, 2 * len(pairs)))
        for hi, lo in pairs:
            lines.append('    0x%016xUL, 0x%016xUL,\n' % (bits(hi), bits(lo)))
        lines.append('};\n')
    table('seed_log_table', 'log(i/128) as hi, lo for i = 96..192', first['LOGC'])
    table('seed_exp2_table', '2^(j/64) as hi, lo for j = 0..63', first['EXP2T'])
    table('seed_atan_table', 'atan(i/32) as hi, lo for i = 0..32', first['ATANT'])
    lines.append('/* 2/pi = sum of word[j] * 2^(-32(j+1)), j = 0..%d */\n' % (TWO_OVER_PI_WORDS - 1))
    lines.append('static const unsigned long seed_two_over_pi[%d] = {\n' % TWO_OVER_PI_WORDS)
    for i in range(0, TWO_OVER_PI_WORDS, 4):
        lines.append('    ' + ' '.join('0x%08xUL,' % w for w in words[i:i + 4]) + '\n')
    lines.append('};\n')
    lines.append(END)
    return ''.join(lines)


def check_header_constants():
    """Each M_* literal in math.h must parse to the binary64 nearest its value."""
    import re
    with localcontext() as ctx:
        ctx.prec = 60
        pi = Fraction(machin_pi(200), 1 << 200)
        e = Fraction(Decimal(1).exp())
        ln2 = Fraction(Decimal(2).ln())
        ln10 = Fraction(Decimal(10).ln())
        sqrt2 = Fraction(Decimal(2).sqrt())
        sqrtpi = Fraction(Decimal(pi.numerator).sqrt() / Decimal(pi.denominator).sqrt())
    expected = {'M_E': e, 'M_LOG2E': 1 / ln2, 'M_LOG10E': 1 / ln10, 'M_LN2': ln2,
                'M_LN10': ln10, 'M_PI': pi, 'M_PI_2': pi / 2, 'M_PI_4': pi / 4,
                'M_1_PI': 1 / pi, 'M_2_PI': 2 / pi, 'M_2_SQRTPI': 2 / sqrtpi,
                'M_SQRT2': sqrt2, 'M_SQRT1_2': sqrt2 / 2}
    header = (ROOT / 'runtime/gcc-seed/include/math.h').read_text()
    found = dict(re.findall(r'^#define (M_\w+) (\S+)$', header, re.M))
    assert set(found) == set(expected), sorted(set(found) ^ set(expected))
    for name, value in expected.items():
        assert float(found[name]) == rn(value), name


def main():
    check_header_constants()
    block = emit()
    if '--print' in sys.argv:
        sys.stdout.write(block)
        return
    text = SOURCE.read_text()
    start = text.index(BEGIN)
    stop = text.index(END) + len(END)
    assert text[start:stop] == block, 'math.c generated tables differ from derivation'
    print('PASS: math.c tables and math.h M_* constants match the integer/Decimal derivation')


if __name__ == '__main__':
    main()
