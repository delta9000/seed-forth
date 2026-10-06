#!/usr/bin/env python3
"""Independent oracles for the seed libm; nothing here is a production input.

1. Host GCC builds of the same original math.c/fpclass.c and fixture at -O0
   and -O2 must reproduce the Forth production records bit for bit (result,
   auxiliary value and errno): a compiler cross-check.
2. The same fixture built against host glibc: exact functions must agree bit
   for bit (NaN sign/payload aside) and every errno must agree; approximate
   functions are measured in ulps.
3. Python Decimal (60+ digits, pi by Machin's formula) gives the true value
   of every approximate record whose result differs from glibc plus a fixed
   sample of the rest; the seed error must stay below the documented bound.
"""
from decimal import Decimal, localcontext
from fractions import Fraction
from pathlib import Path
import argparse
import collections
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/gcc'))
import math_records as M  # noqa: E402

SOURCES = ['runtime/gcc-seed/math.c', 'runtime/gcc-seed/fpclass.c',
           'runtime/gcc-seed/include/math.h', 'tests/gcc/math-fixture.c',
           'tests/gcc/math_records.py', 'tests/gcc/math-oracle-check.py']
# Documented maximum error against the true value, in ulps (MATH.md).
BOUND = 0.501
SAMPLE_STRIDE = 16
PREC = 60


def run(command, data=None, timeout=600):
    result = subprocess.run(list(map(str, command)), input=data, capture_output=True, timeout=timeout)
    assert result.returncode == 0, (command, result.returncode, result.stderr[-2000:])
    return result.stdout


# ---------------------------------------------------------------- Decimal truth

def machin_pi(digits):
    scale = 10 ** (digits + 10)

    def arctan_inv(n):
        total, term, k = 0, scale // n, 0
        while term:
            total += term // (2 * k + 1) if k % 2 == 0 else -(term // (2 * k + 1))
            term //= n * n
            k += 1
        return total
    return Decimal(16 * arctan_inv(5) - 4 * arctan_inv(239)) / Decimal(scale)


with localcontext() as _c:
    _c.prec = 460
    PI_WIDE = machin_pi(450)
    LN2 = Decimal(2).ln()
    LN10 = Decimal(10).ln()


def series(terms, x):
    """sum of terms(k) while they matter (alternating/convergent Taylor)."""
    total = Decimal(0)
    k = 0
    while True:
        t = terms(k)
        total += t
        if t == 0 or abs(t) < abs(total) * Decimal(10) ** -(PREC + 8):
            return total
        k += 1


def d_sin_small(r):
    r2 = r * r
    state = {'t': r}

    def term(k):
        if k:
            state['t'] = -state['t'] * r2 / ((2 * k) * (2 * k + 1))
        return state['t']
    return series(term, r)


def d_cos_small(r):
    r2 = r * r
    state = {'t': Decimal(1)}

    def term(k):
        if k:
            state['t'] = -state['t'] * r2 / ((2 * k - 1) * (2 * k))
        return state['t']
    return series(term, r)


def d_reduce(x):
    """x = n*pi/2 + r with |r| <= pi/4; returns (n mod 4, r) at PREC digits."""
    with localcontext() as c:
        c.prec = 460
        half = PI_WIDE / 2
        n = (x / half).to_integral_value()
        r = x - n * half
    return int(n) % 4, +r


def d_atan(x):
    """arctan for x >= 0 by argument halving and Taylor series."""
    if x == 0:
        return Decimal(0)
    if x > 1:
        return PI_WIDE / 2 - d_atan(1 / x)
    halvings = 0
    while x > Decimal('0.1'):
        x = x / (1 + (1 + x * x).sqrt())
        halvings += 1
    x2 = x * x
    state = {'t': x}

    def term(k):
        if k:
            state['t'] = -state['t'] * x2 * (2 * k - 1) / (2 * k + 1)
        return state['t']
    return series(term, x) * (2 ** halvings)


def d_exp(z):
    """exp with arguments far outside binary64 range clamped to huge/tiny."""
    if z > 3000:
        return Decimal('1e2000')
    if z < -3000:
        return Decimal('1e-2000')
    return z.exp()


def d_expm1(x):
    if abs(x) < Decimal('1e-5'):
        state = {'t': x}

        def term(k):
            if k:
                state['t'] = state['t'] * x / (k + 1)
            return state['t']
        return series(term, x)
    with localcontext() as c:
        c.prec = PREC + 12
        return d_exp(x) - 1


def truth(name, x, y):
    """True value of name(x[, y]) as a Decimal for finite arguments."""
    X = Decimal(x)
    Y = Decimal(y)
    with localcontext() as c:
        c.prec = PREC
        c.Emin = -999999
        c.Emax = 999999
        if name == 'exp':
            return d_exp(X)
        if name == 'exp2':
            return d_exp(X * LN2)
        if name == 'expm1':
            return d_expm1(X)
        if name == 'log':
            return X.ln()
        if name == 'log2':
            return X.ln() / LN2
        if name == 'log10':
            return X.log10()
        if name == 'log1p':
            if abs(X) < Decimal('1e-5'):
                state = {'t': X}

                def term(k):
                    if k:
                        state['t'] = -state['t'] * X * k / (k + 1)
                    return state['t']
                return series(term, X)
            c.prec = PREC + 10
            return (1 + X).ln()
        if name == 'pow':
            sign = -1 if X < 0 and Fraction(y).denominator == 1 and Fraction(y).numerator % 2 else 1
            c.prec = PREC + 10
            return sign * d_exp(Y * abs(X).ln())
        if name == 'cbrt':
            return (1 if X > 0 else -1) * (abs(X).ln() / 3).exp()
        if name == 'hypot':
            c.prec = 2 * PREC
            return (X * X + Y * Y).sqrt()
        if name in ('sin', 'cos', 'tan'):
            n, r = d_reduce(X)
            s, k = d_sin_small(r), d_cos_small(r)
            if name == 'sin':
                return (s, k, -s, -k)[n]
            if name == 'cos':
                return (k, -s, -k, s)[n]
            return s / k if n % 2 == 0 else -k / s
        if name == 'atan':
            return (1 if X > 0 else -1) * d_atan(abs(X))
        if name in ('asin', 'acos'):
            side = ((1 - X) * (1 + X)).sqrt()
            if name == 'asin':
                return (1 if X > 0 else -1) * (d_atan(abs(X) / side) if side else PI_WIDE / 2)
            if X == 0:
                return PI_WIDE / 2
            a = d_atan(side / abs(X))
            return a if X > 0 else PI_WIDE - a
        if name == 'atan2':      # fixture argument order: atan2(x, y), x = ordinate
            a = d_atan(abs(X) / abs(Y)) if Y != 0 else PI_WIDE / 2
            if Y < 0:
                a = PI_WIDE - a
            return a if X > 0 else -a
        if name in ('sinh', 'cosh', 'tanh'):
            if name != 'cosh' and abs(X) < Decimal('1e-5'):
                x2 = X * X
                if name == 'sinh':
                    return X * (1 + x2 / 6 + x2 * x2 / 120)
                return X * (1 - x2 / 3 + 2 * x2 * x2 / 15 - 17 * x2 * x2 * x2 / 315)
            c.prec = PREC + 10
            if abs(X) > 3000:
                if name == 'tanh':
                    return Decimal(1 if X > 0 else -1)
                return Decimal('1e2000') * (1 if X > 0 or name == 'cosh' else -1)
            e = X.exp()
            if name == 'sinh':
                return (e - 1 / e) / 2
            if name == 'cosh':
                return (e + 1 / e) / 2
            e2 = e * e
            return (e2 - 1) / (e2 + 1)
    raise KeyError(name)


MAX_FINITE = Fraction(M.b2d(0x7fefffffffffffff))
OVERFLOW = MAX_FINITE + Fraction(2) ** 970     # values at or above round to infinity


def ulp_error(result_bits, value):
    """Signed error of result against the exact value, in ulps of the value."""
    v = Fraction(value)
    if M.is_inf_bits(result_bits):
        if abs(v) >= OVERFLOW and (result_bits & M.SIGN) == (M.SIGN if v < 0 else 0):
            return 0.0
        return float('inf')
    r = M.bits_fraction(result_bits)
    a = abs(v)
    if a == 0:
        return 0.0 if r == 0 else float('inf')
    e = a.numerator.bit_length() - a.denominator.bit_length()
    if Fraction(2) ** e > a:
        e -= 1
    ulp = Fraction(2) ** max(e - 52, -1074)
    if a >= OVERFLOW:
        ulp = Fraction(2) ** 971
    return float((r - v) / ulp)


# ---------------------------------------------------------------- builds

def host_builds(out, compiler):
    """glibc oracle executable and host builds of the seed sources."""
    include = out / 'seed-math-include'
    include.mkdir()
    shutil.copy(ROOT / 'runtime/gcc-seed/include/math.h', include / 'math.h')
    common = [compiler, '-std=gnu89', '-fno-builtin', '-ffp-contract=off', '-w']
    glibc = out / 'fixture-glibc'
    run(common + ['-O0', ROOT / 'tests/gcc/math-fixture.c', '-o', glibc, '-lm'])
    seeds = {}
    for level in ('-O0', '-O2'):
        executable = out / ('fixture-seed' + level)
        run(common + [level, '-I', include, ROOT / 'tests/gcc/math-fixture.c',
                      ROOT / 'runtime/gcc-seed/math.c', ROOT / 'runtime/gcc-seed/fpclass.c',
                      '-o', executable])
        seeds[level] = executable
    return glibc, seeds


def compare(cases, seed, glibc):
    stats = collections.defaultdict(lambda: {
        'records': 0, 'differ_from_glibc': 0, 'max_ulp_distance_vs_glibc': 0,
        'truth_checked': 0, 'max_seed_error_ulp': 0.0, 'max_glibc_error_ulp': 0.0,
        'nan_sign_differences': 0})
    failures = []
    worst = {}
    for index, ((op, xb, yb), (rb, aux, err), (gb, gaux, gerr)) in enumerate(zip(cases, seed, glibc)):
        name = M.NAME[op]
        s = stats[name]
        s['records'] += 1
        if M.is_nan_bits(rb) and M.is_nan_bits(gb) and rb != gb:
            s['nan_sign_differences'] += 1
        if err != gerr:
            failures.append((name, '%016x' % xb, '%016x' % yb, 'errno', err, gerr))
            continue
        if M.KIND[op] == 'exact':
            same = M.same_result(gb, rb) and (aux == gaux or (name == 'modf' and M.is_nan_bits(xb)))
            if name in ('lround', 'lrint', 'llround', 'llrint', 'classify'):
                same = aux == gaux
            if not same:
                failures.append((name, '%016x' % xb, '%016x' % yb, 'exact', '%016x' % rb, '%016x' % gb, aux, gaux))
            continue
        if M.is_nan_bits(rb) or M.is_nan_bits(gb):
            if M.is_nan_bits(rb) != M.is_nan_bits(gb):
                failures.append((name, '%016x' % xb, '%016x' % yb, 'nan', '%016x' % rb, '%016x' % gb))
            continue
        distance = abs(ordinal(rb) - ordinal(gb))
        if distance:
            s['differ_from_glibc'] += 1
            s['max_ulp_distance_vs_glibc'] = max(s['max_ulp_distance_vs_glibc'], distance)
        finite_in = (xb & M.ABS) < M.INF and ((yb & M.ABS) < M.INF or name not in ('pow', 'hypot', 'atan2'))
        if not finite_in or (rb & M.ABS) >= M.INF and (gb & M.ABS) >= M.INF:
            continue
        if distance == 0 and index % SAMPLE_STRIDE:
            continue
        if name in ('pow',) and (xb & M.ABS) == 0:
            continue
        value = truth(name, M.b2d(xb), M.b2d(yb))
        es = ulp_error(rb, value)
        eg = ulp_error(gb, value)
        s['truth_checked'] += 1
        if abs(es) > s['max_seed_error_ulp']:
            s['max_seed_error_ulp'] = abs(es)
            worst[name] = {'x': '%016x' % xb, 'y': '%016x' % yb, 'seed': '%016x' % rb,
                           'glibc': '%016x' % gb, 'seed_error': es, 'glibc_error': eg}
        s['max_glibc_error_ulp'] = max(s['max_glibc_error_ulp'], abs(eg))
        if not abs(es) < BOUND:
            failures.append((name, '%016x' % xb, '%016x' % yb, 'accuracy', '%016x' % rb, es, '%016x' % gb, eg))
    return stats, worst, failures


def ordinal(b):
    """Monotone integer order of binary64 bits (adjacent values differ by 1)."""
    return -(b & M.ABS) if b & M.SIGN else b


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--production-output', type=Path,
                        help='math-check.py output directory (inputs.bin, results.bin)')
    args = parser.parse_args()
    (ROOT / 'build-out').mkdir(exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix='math-oracle-', dir=ROOT / 'build-out'))
    compiler = shutil.which('gcc')
    assert compiler, 'host GCC is required for this explicitly oracle-only check'
    started = time.time()
    if args.production_output:
        data = (args.production_output / 'inputs.bin').read_bytes()
        cases = M.unpack_inputs(data)
        assert cases == M.generate(), 'production inputs are not the generated record set'
    else:
        cases = M.generate()
        data = M.pack_inputs(cases)
    glibc_exe, seed_exes = host_builds(out, compiler)
    glibc_out = run([glibc_exe], data)
    seed_out = {level: run([exe], data) for level, exe in seed_exes.items()}
    # GCC may swap the operands of a commutative x + y, which only changes
    # which input NaN propagates; every other bit and errno must agree.
    for (r0, a0, e0), (r2, a2, e2) in zip(M.unpack_outputs(seed_out['-O0']), M.unpack_outputs(seed_out['-O2'])):
        assert M.same_result(r0, r2) and a0 == a2 and e0 == e2, 'host optimization changed seed results'
    report = {'proof': 'HOST AND DECIMAL ORACLES ONLY; not a production reconstruction',
              'host_compiler': run([compiler, '--version']).decode().splitlines()[0],
              'host_libc': run(['ldd', '--version']).decode().splitlines()[0],
              'records': len(cases), 'bound_ulp': BOUND, 'decimal_digits': PREC,
              'sample_stride': SAMPLE_STRIDE,
              'source_sha256': {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in SOURCES}}
    if args.production_output:
        production = (args.production_output / 'results.bin').read_bytes()
        assert production == seed_out['-O0'], 'Forth and host builds of the same sources disagree'
        report['production_equals_host_builds'] = True
        report['production_results_sha256'] = hashlib.sha256(production).hexdigest()
    stats, worst, failures = compare(cases, M.unpack_outputs(seed_out['-O0']), M.unpack_outputs(glibc_out))
    report['functions'] = dict(sorted(stats.items()))
    report['worst_seed_cases'] = worst
    report['seconds'] = round(time.time() - started, 1)
    report['failures'] = failures[:200]
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    assert not failures, '%d oracle failures, first %r; see %s' % (len(failures), failures[:5], out / 'report.json')
    print('PASS: seed libm vs host builds, glibc and Decimal truth (bound %.3f ulp)' % BOUND)
    print(out / 'report.json')


if __name__ == '__main__':
    main()
