"""Shared math test records: deterministic inputs, record codecs and exact
references. Original seed-forth test code, MIT license.

Exact references use only Python integers, Fraction and struct (IEEE
hardware arithmetic for single + - * / where noted); Python's math module
(host libm) is never consulted here, so math-check.py stays host-libm free.
"""
from fractions import Fraction
import random
import struct

# id, name, arity, kind ('approx' is compared against oracles in ulps,
# 'exact' must be bit-identical to the exact reference everywhere).
OPERATIONS = [
    (0, 'exp', 1, 'approx'), (1, 'exp2', 1, 'approx'), (2, 'expm1', 1, 'approx'),
    (3, 'log', 1, 'approx'), (4, 'log2', 1, 'approx'), (5, 'log10', 1, 'approx'),
    (6, 'log1p', 1, 'approx'), (7, 'pow', 2, 'approx'), (8, 'cbrt', 1, 'approx'),
    (9, 'hypot', 2, 'approx'), (10, 'sin', 1, 'approx'), (11, 'cos', 1, 'approx'),
    (12, 'tan', 1, 'approx'), (13, 'asin', 1, 'approx'), (14, 'acos', 1, 'approx'),
    (15, 'atan', 1, 'approx'), (16, 'atan2', 2, 'approx'), (17, 'sinh', 1, 'approx'),
    (18, 'cosh', 1, 'approx'), (19, 'tanh', 1, 'approx'),
    (20, 'sqrt', 1, 'exact'), (21, 'fabs', 1, 'exact'), (22, 'floor', 1, 'exact'),
    (23, 'ceil', 1, 'exact'), (24, 'trunc', 1, 'exact'), (25, 'round', 1, 'exact'),
    (26, 'rint', 1, 'exact'), (27, 'nearbyint', 1, 'exact'), (28, 'lround', 1, 'exact'),
    (29, 'lrint', 1, 'exact'), (30, 'llround', 1, 'exact'), (31, 'llrint', 1, 'exact'),
    (32, 'fmod', 2, 'exact'), (33, 'remainder', 2, 'exact'), (34, 'fmin', 2, 'exact'),
    (35, 'fmax', 2, 'exact'), (36, 'fdim', 2, 'exact'), (37, 'frexp', 1, 'exact'),
    (38, 'ldexp', 2, 'exact'), (39, 'scalbn', 2, 'exact'), (40, 'modf', 1, 'exact'),
    (41, 'copysign', 2, 'exact'), (42, 'classify', 2, 'exact'),
]
NAME = {op: name for op, name, arity, kind in OPERATIONS}
ID = {name: op for op, name, arity, kind in OPERATIONS}
KIND = {op: kind for op, name, arity, kind in OPERATIONS}
UNTOUCHED = 123
EDOM = 33
ERANGE = 34
SIGN = 1 << 63
ABS = SIGN - 1
INF = 0x7ff0000000000000
QNAN = 0x7ff8000000000000
LONG_MIN_BITS = 1 << 63


def d2b(x):
    return struct.unpack('<Q', struct.pack('<d', x))[0]


def b2d(b):
    return struct.unpack('<d', struct.pack('<Q', b & 0xffffffffffffffff))[0]


def is_nan_bits(b):
    return (b & ABS) > INF


def is_inf_bits(b):
    return (b & ABS) == INF


def fraction_to_bits(value):
    """Correctly rounded binary64 bits of a Fraction (ties to even)."""
    if value == 0:
        return 0
    negative = value < 0
    try:
        bits = d2b(float(abs(value)))      # int/int true division is exact-rounded
    except OverflowError:
        bits = INF
    return bits | (SIGN if negative else 0)


def bits_fraction(b):
    return Fraction(b2d(b))


def next_up_bits(b):
    """Next representable value toward +inf (finite b)."""
    if b == SIGN:
        return 1
    if b & SIGN:
        return b - 1
    return b + 1


def ulp_of_bits(b):
    """Spacing of the binade containing |b| (finite), as a Fraction."""
    exponent = (b >> 52) & 2047
    return Fraction(2) ** (max(exponent, 1) - 1075)


# ---------------------------------------------------------------- inputs

class Generator:
    def __init__(self, seed):
        self.random = random.Random(seed)
        self.cases = []

    def add(self, name, x, y=0):
        self.cases.append((ID[name], x & 0xffffffffffffffff, y & 0xffffffffffffffff))

    def bits(self):
        return self.random.getrandbits(64)

    def finite_bits(self):
        while True:
            b = self.random.getrandbits(64)
            if (b & ABS) < INF:
                return b

    def uniform(self, low, high):
        return d2b(self.random.uniform(low, high))

    def scaled(self, low_exponent, high_exponent, signed=True):
        """Random significand with an exponent uniform in a range."""
        e = self.random.randint(low_exponent, high_exponent)
        b = ((e + 1023) << 52) | self.random.getrandbits(52)
        if e < -1022:
            b = self.random.getrandbits(52) >> self.random.randint(0, 51)
        if signed and self.random.getrandbits(1):
            b |= SIGN
        return b


SPECIAL_VALUES = [
    0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 2.0, -2.0, 3.0, -3.0, 1.5, -1.5,
    b2d(1), b2d(SIGN | 1), b2d(0x000fffffffffffff), b2d(0x800fffffffffffff),
    b2d(0x0010000000000000), b2d(0x8010000000000000),
    b2d(0x7fefffffffffffff), b2d(0xffefffffffffffff),
    b2d(INF), b2d(SIGN | INF), b2d(QNAN), b2d(SIGN | QNAN),
    b2d(0x3ff0000000000001), b2d(0x3fefffffffffffff), b2d(0xbff0000000000001),
    b2d(0xbfefffffffffffff), 1e-300, -1e-300, 1e300, -1e300, 0.25, 4.0, 10.0,
    -10.0, 100.0, 1e22, 2.0 ** 52, 2.0 ** 53, -(2.0 ** 63), 2.0 ** 63,
]
SPECIAL_BITS = [d2b(v) for v in SPECIAL_VALUES]


def neighbours(g, name, value, count, y=None):
    b = d2b(value)
    for k in range(-count, count + 1):
        c = b + k
        if c & SIGN != b & SIGN or (c & ABS) >= INF:
            continue
        if y is None:
            g.add(name, c)
        else:
            g.add(name, c, y)


def generate(seed=0x5eed):
    g = Generator(seed)
    one = [name for op, name, arity, kind in OPERATIONS if arity == 1]
    two = [name for op, name, arity, kind in OPERATIONS if arity == 2]
    # Every special value for every operation; all pairs for binary ones.
    for name in one:
        for b in SPECIAL_BITS:
            g.add(name, b)
    for name in two:
        for b in SPECIAL_BITS:
            for c in SPECIAL_BITS:
                if name in ('ldexp', 'scalbn'):
                    continue
                g.add(name, b, c)
    # Uniform random bit patterns over every class and exponent.
    for name in one:
        for _ in range(12000):
            g.add(name, g.bits())
    for name in two:
        if name in ('ldexp', 'scalbn'):
            continue
        for _ in range(12000):
            g.add(name, g.bits(), g.bits())

    # ---- exponentials
    for _ in range(25000):
        g.add('exp', g.uniform(-750.0, 712.0))
        g.add('exp', g.uniform(-2.0, 2.0))
        g.add('exp2', g.uniform(-1080.0, 1025.0))
        g.add('exp2', g.uniform(-2.0, 2.0))
        g.add('expm1', g.uniform(-45.0, 711.0))
        g.add('expm1', g.uniform(-1.0, 1.0))
        g.add('expm1', g.scaled(-60, -1))
    for k in range(-1080, 1030):
        g.add('exp2', d2b(float(k)))
        g.add('exp2', d2b(k + 0.5))
    for k in range(-750, 712):
        g.add('exp', d2b(float(k)))
    for value in (709.782712893384, -745.1332191019411, -708.3964185322641,
                  -745.1332191019412, 0.005, -0.005, 0.0054152123481245725):
        neighbours(g, 'exp', value, 40)
        neighbours(g, 'expm1', value, 40)
    for value in (1024.0, -1022.0, -1074.0, -1075.0, -1076.0):
        neighbours(g, 'exp2', value, 40)
    for _ in range(4000):
        g.add('exp', g.scaled(-80, -20))
        g.add('exp2', g.scaled(-80, -20))

    # ---- logarithms
    for name in ('log', 'log2', 'log10', 'log1p'):
        for _ in range(20000):
            g.add(name, g.scaled(-1074, 1023, signed=False))
            g.add(name, g.uniform(0.5, 2.0))
        for _ in range(6000):
            g.add(name, d2b(1.0) + g.random.randint(-2 ** 40, 2 ** 40))
        neighbours(g, name, 1.0, 200)
    for k in range(-1074, 1024):
        g.add('log2', d2b(2.0 ** k))
        g.add('log', d2b(2.0 ** k))
    for n in range(-323, 309):
        g.add('log10', d2b(float('1e%d' % n)))
    for _ in range(20000):
        g.add('log1p', g.uniform(-1.0, 1.0))
        g.add('log1p', g.scaled(-60, -1))
    neighbours(g, 'log1p', -1.0, 100)

    # ---- power
    for _ in range(40000):
        x = g.scaled(-1074, 1023, signed=False)
        lg = abs(Fraction(b2d(x)).numerator.bit_length() - Fraction(b2d(x)).denominator.bit_length()) + 1
        g.add('pow', x, d2b(g.random.uniform(-1, 1) * 1100.0 / lg))
        g.add('pow', g.uniform(0.0, 4.0), g.uniform(-60.0, 60.0))
        g.add('pow', d2b(1.0) + g.random.randint(-2 ** 30, 2 ** 30),
              d2b(g.random.uniform(-1, 1) * 2.0 ** g.random.randint(10, 60)))
        g.add('pow', g.uniform(-30.0, 30.0), d2b(float(g.random.randint(-200, 200))))
    for base in range(-40, 41):
        for power in range(-80, 81):
            g.add('pow', d2b(float(base)), d2b(float(power)))
    for k in range(-1074, 1024):
        g.add('pow', d2b(2.0), d2b(float(k)))
        g.add('pow', d2b(0.5), d2b(float(k)))
    for root in range(0, 3000):
        g.add('pow', d2b(float(root * root)), d2b(0.5))
    for _ in range(3000):
        root = g.random.getrandbits(26)
        g.add('pow', d2b(float(root * root) * 4.0 ** g.random.randint(-200, 200)), d2b(0.5))

    # ---- cube root and hypotenuse
    for _ in range(20000):
        g.add('cbrt', g.uniform(-10.0, 10.0))
        g.add('hypot', g.uniform(-10.0, 10.0), g.uniform(-10.0, 10.0))
        g.add('hypot', g.scaled(-1074, -1000), g.scaled(-1074, -1000))
        g.add('hypot', g.scaled(1000, 1023), g.scaled(990, 1023))
        e = g.random.randint(-1074, 1023)
        g.add('hypot', g.scaled(e, e), g.scaled(max(e - 30, -1074), e))
    for k in range(1, 3000):
        g.add('cbrt', d2b(float(k ** 3)))
        g.add('cbrt', d2b(-float(k ** 3) * 8.0 ** g.random.randint(-300, 300)))
    for _ in range(3000):
        k = g.random.getrandbits(17)
        g.add('cbrt', d2b(float(k ** 3) * 8.0 ** g.random.randint(-340, 300)))
    for a, b, c in ((3, 4, 5), (5, 12, 13), (8, 15, 17), (20, 21, 29), (119, 120, 169)):
        for j in range(-1070, 1015, 7):
            g.add('hypot', d2b(a * 2.0 ** j), d2b(b * 2.0 ** j))

    # ---- circular and hyperbolic
    for name in ('sin', 'cos', 'tan'):
        for _ in range(25000):
            g.add(name, g.uniform(-10.0, 10.0))
            g.add(name, g.scaled(-30, 1023))
        for _ in range(8000):
            g.add(name, g.uniform(-1048576.0, 1048576.0))
            g.add(name, g.scaled(19, 21))
        for n in range(1, 4000):
            neighbours(g, name, n * 1.5707963267948966, 1)
        for _ in range(3000):
            neighbours(g, name, g.random.randint(1, 2 ** 40) * 1.5707963267948966, 0)
        for x in (6381956970095103 * 2.0 ** 797, 5319372648451847 * 2.0 ** 717,
                  6381956970095103 * 2.0 ** -797 * 2.0 ** 797, 1e22, 2.0 ** 1023, 0.7853981633974483):
            neighbours(g, name, x, 20)
    for name in ('asin', 'acos'):
        for _ in range(25000):
            g.add(name, g.uniform(-1.0, 1.0))
            g.add(name, g.scaled(-60, -1))
        for _ in range(5000):
            g.add(name, d2b(1.0) - g.random.randint(1, 2 ** 40))
            g.add(name, d2b(-1.0) - g.random.randint(1, 2 ** 40))
        neighbours(g, name, 1.0, 50)
        neighbours(g, name, -1.0, 50)
        neighbours(g, name, 0.5, 50)
    for _ in range(25000):
        g.add('atan', g.uniform(-10.0, 10.0))
        g.add('atan', g.scaled(-60, 80))
        g.add('atan2', g.uniform(-10.0, 10.0), g.uniform(-10.0, 10.0))
        e = g.random.randint(-1074, 1023)
        g.add('atan2', g.scaled(e, e), g.scaled(max(e - 70, -1074), min(e + 70, 1023)))
    for name in ('sinh', 'cosh', 'tanh'):
        for _ in range(25000):
            g.add(name, g.uniform(-30.0, 30.0))
            g.add(name, g.uniform(-1.0, 1.0))
            g.add(name, g.scaled(-60, -1))
        for _ in range(5000):
            g.add(name, g.uniform(-760.0, 760.0))
        for value in (710.4758600739439, -710.4758600739439, 22.0, -22.0, 1.0, 0.005):
            neighbours(g, name, value, 30)

    # ---- square root
    for _ in range(40000):
        g.add('sqrt', g.scaled(-1074, 1023, signed=False))
        root = g.random.getrandbits(26) | 1
        g.add('sqrt', d2b(float(root * root) * 4.0 ** g.random.randint(-250, 250)))
    for _ in range(5000):
        g.add('sqrt', g.random.getrandbits(52))   # subnormals
    # A million more: random positive finite bit patterns (every exponent
    # and subnormals), and squares of rounding midpoints, whose roots lie
    # within a fraction of an ulp of a rounding boundary.
    for _ in range(800000):
        g.add('sqrt', g.random.getrandbits(63) % INF)
    for _ in range(200000):
        midpoint = (((1 << 52) | g.random.getrandbits(52)) << 1) | 1
        square = Fraction(midpoint * midpoint) * Fraction(4) ** g.random.randint(-590, 457)
        g.add('sqrt', fraction_to_bits(square) + g.random.randint(-2, 2))

    # ---- rounding to integers
    rounding = ('floor', 'ceil', 'trunc', 'round', 'rint', 'nearbyint',
                'lround', 'lrint', 'llround', 'llrint')
    for name in rounding:
        for _ in range(12000):
            g.add(name, g.scaled(-3, 70))
            n = g.random.randint(-2 ** 52, 2 ** 52)
            g.add(name, d2b(n + 0.5))
            g.add(name, d2b(n + 0.5) + g.random.choice((-1, 1)))
            scale = 2.0 ** g.random.randint(0, 51)
            g.add(name, d2b((g.random.randint(-2 ** 20, 2 ** 20) + 0.5) / scale * scale))
        for value in (0.5, 1.5, 2.5, -0.5, -1.5, -2.5, 2.0 ** 52, 2.0 ** 63, -(2.0 ** 63),
                      2.0 ** 52 + 0.5, 4503599627370495.5, 9.2233720368547748e18):
            neighbours(g, name, value, 6)

    # ---- remainders
    for name in ('fmod', 'remainder'):
        for _ in range(20000):
            g.add(name, g.uniform(-1e6, 1e6), g.uniform(-100.0, 100.0))
            y = g.scaled(-1074, 1023)
            k = g.random.randint(-2 ** 40, 2 ** 40)
            x = fraction_to_bits(Fraction(b2d(y)) * k + Fraction(b2d(y)) * Fraction(g.random.choice((0, 1, -1)), 2))
            if not is_inf_bits(x):
                g.add(name, x, y)
            e = g.random.randint(-1074, 1023)
            g.add(name, g.scaled(e, e), g.scaled(-1074, e))
        for k in range(1, 400):
            g.add(name, d2b(k * 0.5), d2b(1.0))
            g.add(name, d2b(-k * 1.5), d2b(3.0))

    for name in ('fmin', 'fmax', 'fdim', 'copysign', 'classify'):
        for _ in range(6000):
            g.add(name, g.uniform(-10.0, 10.0), g.uniform(-10.0, 10.0))
    for _ in range(4000):
        g.add('fdim', g.scaled(1020, 1023), g.scaled(1020, 1023))

    # ---- frexp, ldexp, scalbn, modf
    for _ in range(20000):
        g.add('frexp', g.bits())
        g.add('modf', g.scaled(-10, 60))
        for name in ('ldexp', 'scalbn'):
            g.add(name, g.bits(), g.random.randint(-2200, 2200))
            g.add(name, g.finite_bits(), g.random.randint(-1100, 1100))
            g.add(name, g.scaled(-10, 10), g.random.randint(-1130, -1020))
    for name in ('ldexp', 'scalbn'):
        for b in SPECIAL_BITS:
            for n in (0, 1, -1, 1023, -1022, -1074, -1075, 2000, -2000,
                      2 ** 31 - 1, -2 ** 31, 60, -60):
                g.add(name, b, n)
        for m in range(1, 64):
            for n in range(-1080, -1018):
                g.add(name, d2b(1.0 + m / 64.0), n)
    return g.cases


# ---------------------------------------------------------------- codecs

def pack_inputs(cases):
    return b''.join(struct.pack('<QQQ', op, x, y) for op, x, y in cases)


def unpack_inputs(data):
    return list(struct.iter_unpack('<QQQ', data))


def unpack_outputs(data):
    return list(struct.iter_unpack('<QqQ', data))


# ---------------------------------------------------------------- exact references

def _signed_zero_like(x_bits):
    return x_bits & SIGN


def _integral(x_bits, mode):
    """floor/ceil/trunc/round/rint of finite x as result bits."""
    x = bits_fraction(x_bits)
    if mode == 'floor':
        n = x.__floor__()
    elif mode == 'ceil':
        n = x.__ceil__()
    elif mode == 'trunc':
        n = int(x)
    elif mode == 'round':
        n = (abs(x) + Fraction(1, 2)).__floor__() * (1 if x >= 0 else -1)
    else:
        n = round(x)          # Fraction rounding is ties-to-even
    if n == 0:
        return _signed_zero_like(x_bits)
    return fraction_to_bits(Fraction(n))


def _long(x_bits, mode):
    if (x_bits & ABS) >= INF:
        return -2 ** 63
    n = bits_fraction(_integral(x_bits, mode))
    if -2 ** 63 <= n < 2 ** 63:
        return int(n)
    return -2 ** 63


def _integer_and_exponent(x_bits):
    """Finite nonzero |x| = n * 2^e with integer n."""
    field = (x_bits >> 52) & 2047
    n = x_bits & 0x000fffffffffffff
    if field:
        return n | (1 << 52), field - 1075
    return n, -1074


def _sqrt_bits(x_bits):
    """Correctly rounded square root: an integer root with at least 60 bits
    plus a sticky half unit decides the single binary64 rounding."""
    import math as integer_only  # isqrt is integer arithmetic, not libm
    n, e = _integer_and_exponent(x_bits)
    if e % 2:
        n <<= 1
        e -= 1
    s = max(0, (130 - n.bit_length()) // 2)
    big = n << (2 * s)
    r = integer_only.isqrt(big)
    sticky = 0 if r * r == big else 1
    return fraction_to_bits(Fraction(2 * r + sticky, 2) * Fraction(2) ** (e // 2 - s))


def _remainder_bits(x_bits, y_bits, nearest):
    x, y = bits_fraction(x_bits), bits_fraction(y_bits)
    q = x / y
    n = round(q) if nearest else int(q)
    r = x - n * y
    if r == 0:
        return _signed_zero_like(x_bits)
    return fraction_to_bits(r)


def exact_reference(op, x_bits, y_bits):
    """Expected (result_bits or None for NaN, aux, errno) of an exact operation."""
    name = NAME[op]
    x, y = b2d(x_bits), b2d(y_bits)
    xnan, ynan = is_nan_bits(x_bits), is_nan_bits(y_bits)
    xinf, yinf = is_inf_bits(x_bits), is_inf_bits(y_bits)
    ax = x_bits & ABS
    NAN = None
    if name == 'sqrt':
        if xnan:
            return NAN, 0, UNTOUCHED
        if ax == 0:
            return x_bits, 0, UNTOUCHED
        if x_bits & SIGN:
            return NAN, 0, EDOM
        if xinf:
            return x_bits, 0, UNTOUCHED
        return _sqrt_bits(x_bits), 0, UNTOUCHED
    if name == 'fabs':
        return (NAN if xnan else ax), 0, UNTOUCHED
    if name in ('floor', 'ceil', 'trunc', 'round', 'rint', 'nearbyint'):
        if xnan:
            return NAN, 0, UNTOUCHED
        if xinf:
            return x_bits, 0, UNTOUCHED
        return _integral(x_bits, 'rint' if name == 'nearbyint' else name), 0, UNTOUCHED
    if name in ('lround', 'llround'):
        return 0, _long(x_bits if not xnan else INF, 'round'), UNTOUCHED
    if name in ('lrint', 'llrint'):
        return 0, _long(x_bits if not xnan else INF, 'rint'), UNTOUCHED
    if name in ('fmod', 'remainder'):
        if xnan or ynan:
            return NAN, 0, UNTOUCHED
        if xinf or (y_bits & ABS) == 0:
            return NAN, 0, EDOM
        if yinf:
            return x_bits, 0, UNTOUCHED
        return _remainder_bits(x_bits, y_bits, name == 'remainder'), 0, UNTOUCHED
    if name in ('fmin', 'fmax'):
        if (xnan and not x_bits & (1 << 51)) or (ynan and not y_bits & (1 << 51)):
            return NAN, 0, UNTOUCHED     # a signaling NaN operand gives NaN
        if xnan and ynan:
            return NAN, 0, UNTOUCHED
        if xnan:
            return y_bits, 0, UNTOUCHED
        if ynan:
            return x_bits, 0, UNTOUCHED
        if name == 'fmin':
            return (x_bits if x < y else y_bits), 0, UNTOUCHED
        return (x_bits if x > y else y_bits), 0, UNTOUCHED
    if name == 'fdim':
        if xnan or ynan:
            return NAN, 0, UNTOUCHED
        if not x > y:
            return 0, 0, UNTOUCHED
        r = d2b(x - y)        # one IEEE subtraction
        error = ERANGE if is_inf_bits(r) and not xinf and not yinf else UNTOUCHED
        return r, 0, error
    if name == 'frexp':
        if xnan:
            return NAN, 0, UNTOUCHED
        if xinf or ax == 0:
            return x_bits, 0, UNTOUCHED
        n, e = _integer_and_exponent(ax)
        e += n.bit_length()       # |x| = (n / 2^bits) * 2^e, n / 2^bits in [1/2, 1)
        return fraction_to_bits(Fraction(n, 1 << n.bit_length())) | (x_bits & SIGN), e, UNTOUCHED
    if name in ('ldexp', 'scalbn'):
        n = struct.unpack('<q', struct.pack('<Q', y_bits))[0]
        n = struct.unpack('<i', struct.pack('<I', n & 0xffffffff))[0]
        if xnan:
            return NAN, 0, UNTOUCHED
        if xinf or ax == 0:
            return x_bits, 0, UNTOUCHED
        r = fraction_to_bits(bits_fraction(x_bits) * Fraction(2) ** n) if abs(n) < 5000 else \
            ((x_bits & SIGN) | (INF if n > 0 else 0))
        if (r & ABS) == 0:
            r = x_bits & SIGN
        error = ERANGE if is_inf_bits(r) or (r & ABS) == 0 else UNTOUCHED
        return r, 0, error
    if name == 'modf':
        if xnan:
            return NAN, 0, UNTOUCHED     # aux (integral part) checked separately
        if xinf:
            return x_bits & SIGN, struct.unpack('<q', struct.pack('<Q', x_bits))[0], UNTOUCHED
        whole = _integral(x_bits, 'trunc')
        part = bits_fraction(x_bits) - bits_fraction(whole)
        frac = (x_bits & SIGN) if part == 0 else fraction_to_bits(part)
        return frac, struct.unpack('<q', struct.pack('<Q', whole))[0], UNTOUCHED
    if name == 'copysign':
        return (ax | (y_bits & SIGN)) if not xnan else NAN, 0, UNTOUCHED
    if name == 'classify':
        if xnan:
            cls = 0
        elif xinf:
            cls = 1
        elif ax == 0:
            cls = 2
        elif ax < 0x0010000000000000:
            cls = 3
        else:
            cls = 4
        aux = cls | (1 if x_bits & SIGN else 0) << 4 | (cls == 0) << 5 | (cls == 1) << 6
        aux |= (cls >= 2) << 7 | (cls == 4) << 8 | (xnan or ynan) << 9
        aux |= (x < y or x > y) << 10 | (x > y) << 11 | (x < y) << 12
        return 0, aux, UNTOUCHED
    raise KeyError(name)


def same_result(expected_bits, actual_bits):
    """Bit equality, except that any NaN matches any NaN (sign/payload aside)."""
    if expected_bits is None or is_nan_bits(expected_bits):
        return is_nan_bits(actual_bits)
    return expected_bits == actual_bits
