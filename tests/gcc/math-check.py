#!/usr/bin/env python3
"""Forth-only build and execution of the libm fixture, checked against exact
references and the documented special-value/errno contract. Host libm, host
compilers and host linkers are not used; oracle comparisons are separate
(math-oracle-check.py --production-output DIR)."""
from fractions import Fraction
from pathlib import Path
import collections
import hashlib
import json
import math as integer_only  # isqrt only: integer arithmetic, never libm
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/gcc'))
import math_records as M  # noqa: E402

SOURCES = ['runtime/gcc-seed/math.c', 'runtime/gcc-seed/fpclass.c',
           'runtime/gcc-seed/include/math.h', 'tests/gcc/math-fixture.c',
           'tests/gcc/math_records.py', 'tests/gcc/math-check.py']
INF = float('inf')


def run(command, data=None, timeout=300):
    result = subprocess.run(list(map(str, command)), input=data, capture_output=True, timeout=timeout)
    assert result.returncode == 0, (command, result.returncode, result.stderr[-2000:])
    assert not result.stderr, (command, result.stderr[-2000:])
    return result.stdout


def machin_pi_fraction(bits=200):
    scale = 1 << (bits + 32)

    def arctan_inv(n):
        total, term, k = 0, scale // n, 0
        while term:
            total += term // (2 * k + 1) if k % 2 == 0 else -(term // (2 * k + 1))
            term //= n * n
            k += 1
        return total
    return Fraction(16 * arctan_inv(5) - 4 * arctan_inv(239), scale)


PI = machin_pi_fraction()
PI_BITS = M.fraction_to_bits(PI)
PIO2_BITS = M.fraction_to_bits(PI / 2)
PIO4_BITS = M.fraction_to_bits(PI / 4)
THREEPIO4_BITS = M.fraction_to_bits(3 * PI / 4)
ONE = M.d2b(1.0)


def integer_class(y):
    """0 non-integer, 1 odd integer, 2 even integer (finite y)."""
    f = Fraction(y)
    if f.denominator != 1:
        return 0
    return 1 if f.numerator % 2 else 2


def exact_root(value, degree):
    """The rational degree-th root of a positive Fraction, or None."""
    def root(n):
        if degree == 2:
            r = integer_only.isqrt(n)
        else:
            r = 1 << ((n.bit_length() + 2) // 3)      # integer Newton from above
            while True:
                s = (2 * r + n // (r * r)) // 3
                if s >= r:
                    break
                r = s
        return r if r ** degree == n else None
    num, den = root(value.numerator), root(value.denominator)
    if num is None or den is None:
        return None
    return Fraction(num, den)


def domain_error(name, x, y):
    nan = x != x or y != y
    if name in ('log', 'log2', 'log10'):
        return not nan and x < 0
    if name == 'log1p':
        return not nan and x < -1
    if name in ('sin', 'cos', 'tan'):
        return abs(x) == INF
    if name in ('asin', 'acos'):
        return not nan and abs(x) > 1
    if name == 'pow':
        return (not nan and x < 0 and abs(x) != INF and abs(y) != INF
                and y != 0 and integer_class(y) == 0)
    return False


def pole_error(name, x, y):
    if name in ('log', 'log2', 'log10'):
        return x == 0
    if name == 'log1p':
        return x == -1
    if name == 'pow':
        return x == 0 and y < 0 and y != -INF
    return False


def contract(name, xb, yb):
    """Exact (result bits, errno) required independently of any libm, or None."""
    x, y = M.b2d(xb), M.b2d(yb)
    sx = xb & M.SIGN
    if name in ('exp', 'exp2'):
        if x == 0:
            return ONE, M.UNTOUCHED
        if x == INF:
            return M.INF, M.UNTOUCHED
        if x == -INF:
            return 0, M.UNTOUCHED
        if name == 'exp2' and x == x and x == int(x) and abs(x) < 4000:
            r = M.fraction_to_bits(Fraction(2) ** int(x))
            return r, (M.ERANGE if r in (0, M.INF) else M.UNTOUCHED)
    if name == 'expm1':
        if x == 0 or x == INF:
            return xb, M.UNTOUCHED
        if x == -INF:
            return M.d2b(-1.0), M.UNTOUCHED
    if name in ('log', 'log2', 'log10'):
        if x == 1:
            return 0, M.UNTOUCHED
        if x == INF:
            return M.INF, M.UNTOUCHED
        if x == 0:
            return M.SIGN | M.INF, M.ERANGE
        if x > 0:
            f = Fraction(x)
            if name == 'log2' and 1 in (f.numerator, f.denominator) \
                    and f.numerator & (f.numerator - 1) == 0 and f.denominator & (f.denominator - 1) == 0:
                return M.d2b(float(f.numerator.bit_length() - f.denominator.bit_length())), M.UNTOUCHED
            if name == 'log10' and f.denominator == 1 and str(f.numerator).rstrip('0') == '1':
                return M.d2b(float(len(str(f.numerator)) - 1)), M.UNTOUCHED
    if name == 'log1p':
        if x == 0 or x == INF:
            return xb, M.UNTOUCHED
        if x == -1:
            return M.SIGN | M.INF, M.ERANGE
    if name == 'pow':
        if y == 0 or x == 1:
            return ONE, M.UNTOUCHED
        if x != x or y != y:
            return None
        cls = integer_class(y) if abs(y) != INF else 2
        neg = bool(sx) and cls == 1
        if abs(y) == INF:
            if abs(x) == 1:
                return ONE, M.UNTOUCHED
            return (0 if (abs(x) < 1) == (y > 0) else M.INF), M.UNTOUCHED
        if x == 0:
            if y < 0:
                return (M.SIGN if neg else 0) | M.INF, M.ERANGE
            return (M.SIGN if neg else 0), M.UNTOUCHED
        if abs(x) == INF:
            return (M.SIGN if neg else 0) | (0 if y < 0 else M.INF), M.UNTOUCHED
        if cls != 0 and abs(y) <= 1100 and (abs(Fraction(x).numerator) > 1 or Fraction(x).denominator > 1):
            value = Fraction(x) ** int(y)
            b = M.fraction_to_bits(value)
            if (b & M.ABS) < M.INF and (b & M.ABS) and M.bits_fraction(b) == value:
                return b, M.UNTOUCHED          # exactly representable power
        if y == 0.5 and x > 0:
            r = exact_root(Fraction(x), 2)
            if r is not None:
                return M.fraction_to_bits(r), M.UNTOUCHED
    if name == 'cbrt':
        if x == 0 or abs(x) == INF:
            return xb, M.UNTOUCHED
        if x == x:
            r = exact_root(abs(Fraction(x)), 3)
            if r is not None:
                return M.fraction_to_bits(r) | sx, M.UNTOUCHED
    if name == 'hypot':
        if abs(x) == INF or abs(y) == INF:
            return M.INF, M.UNTOUCHED
        if x == x and y == y:
            r = exact_root(Fraction(x) ** 2 + Fraction(y) ** 2, 2)
            if r is not None:
                b = M.fraction_to_bits(r)
                return b, (M.ERANGE if b == M.INF else M.UNTOUCHED)
    if name in ('sin', 'tan', 'asin', 'atan', 'sinh', 'tanh') and x == 0:
        return xb, M.UNTOUCHED
    if name in ('cos', 'cosh') and x == 0:
        return ONE, M.UNTOUCHED
    if name == 'acos' and x == 1:
        return 0, M.UNTOUCHED
    if name == 'acos' and x == -1:
        return PI_BITS, M.UNTOUCHED
    if name == 'asin' and abs(x) == 1:
        return PIO2_BITS | sx, M.UNTOUCHED
    if name == 'atan' and abs(x) == INF:
        return PIO2_BITS | sx, M.UNTOUCHED
    if name == 'sinh' and abs(x) == INF:
        return xb, M.UNTOUCHED
    if name == 'cosh' and abs(x) == INF:
        return M.INF, M.UNTOUCHED
    if name == 'tanh' and abs(x) == INF:
        return ONE | sx, M.UNTOUCHED
    if name == 'atan2' and x == x and y == y:
        # C99 F.9.1.4; the fixture passes atan2(x, y), so x is the ordinate.
        sy, sxx = xb & M.SIGN, yb & M.SIGN
        if x == 0:
            return (xb if sxx == 0 else PI_BITS | sy), M.UNTOUCHED
        if y == 0:
            return PIO2_BITS | sy, M.UNTOUCHED
        if abs(x) == INF and abs(y) == INF:
            return (THREEPIO4_BITS if sxx else PIO4_BITS) | sy, M.UNTOUCHED
        if abs(y) == INF:
            return (PI_BITS if sxx else 0) | sy, M.UNTOUCHED
        if abs(x) == INF:
            return PIO2_BITS | sy, M.UNTOUCHED
    return None


def check_approx(name, xb, yb, rb, error, failures):
    x, y = M.b2d(xb), M.b2d(yb)
    expected = contract(name, xb, yb)
    if expected is not None:
        eb, ee = expected
        if not (M.same_result(eb, rb) and error == ee):
            failures.append((name, '%016x' % xb, '%016x' % yb, '%016x' % rb, error,
                             'contract', '%016x' % eb, ee))
        return
    if M.is_nan_bits(xb) or (M.is_nan_bits(yb) and name in ('pow', 'hypot', 'atan2')):
        ok = M.is_nan_bits(rb) and error == M.UNTOUCHED
    elif domain_error(name, x, y):
        ok = M.is_nan_bits(rb) and error == M.EDOM
    elif pole_error(name, x, y):
        ok = M.is_inf_bits(rb) and error == M.ERANGE
    else:
        finite = (xb & M.ABS) < M.INF and (name not in ('pow', 'hypot', 'atan2') or (yb & M.ABS) < M.INF)
        ok = not M.is_nan_bits(rb)
        # Range errors: overflow, or underflow to zero of a nonzero result.
        if finite and (M.is_inf_bits(rb) or ((rb & M.ABS) == 0 and (
                name in ('exp', 'exp2') or (name in ('pow', 'atan2') and x != 0)))):
            ok = ok and error == M.ERANGE
        else:
            ok = ok and error == M.UNTOUCHED
    if not ok:
        failures.append((name, '%016x' % xb, '%016x' % yb, '%016x' % rb, error, 'errno-rule'))


def check_records(cases, outputs):
    failures = []
    counts = collections.Counter()
    for (op, xb, yb), (rb, aux, error) in zip(cases, outputs):
        name = M.NAME[op]
        counts[name] += 1
        if M.KIND[op] == 'exact':
            eb, eaux, eerr = M.exact_reference(op, xb, yb)
            ok = M.same_result(eb, rb) and error == eerr
            if name in ('lround', 'lrint', 'llround', 'llrint', 'frexp', 'classify'):
                ok = ok and aux == eaux
            if name == 'modf':
                ok = ok and (M.is_nan_bits(aux & 0xffffffffffffffff) if M.is_nan_bits(xb) else aux == eaux)
            if not ok:
                failures.append((name, '%016x' % xb, '%016x' % yb, '%016x' % rb, aux, error, 'exact',
                                 None if eb is None else '%016x' % eb, eaux, eerr))
        else:
            check_approx(name, xb, yb, rb, error, failures)
    return counts, failures


def main():
    (ROOT / 'build-out').mkdir(exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix='math-production-', dir=ROOT / 'build-out'))
    compiler = [sys.executable, ROOT / 'tools/gcc-direct-cc.py']
    identity = run(compiler + ['--print-source-hash']).decode().strip()
    executable = out / 'math-fixture'
    start = time.time()
    run(compiler + ['-o', executable, ROOT / 'tests/gcc/math-fixture.c', '-lm'])
    built = time.time()
    cases = M.generate()
    data = M.pack_inputs(cases)
    (out / 'inputs.bin').write_bytes(data)
    results = run([executable], data)
    ran = time.time()
    (out / 'results.bin').write_bytes(results)
    outputs = M.unpack_outputs(results)
    assert len(outputs) == len(cases), (len(outputs), len(cases))
    counts, failures = check_records(cases, outputs)
    checked = time.time()
    (out / 'failures.json').write_text(json.dumps(failures[:2000], indent=1) + '\n')
    assert not failures, 'math contract failures: %d (first: %r); see %s' % (
        len(failures), failures[:5], out / 'failures.json')
    assert identity == run(compiler + ['--print-source-hash']).decode().strip()
    report = {
        'proof': 'Forth C compiler, Forth archive writer and Forth linker; no host objects or library',
        'compiler_source_identity': identity,
        'records': len(cases), 'records_per_function': dict(sorted(counts.items())),
        'exact_functions': 'bit-identical to Fraction/integer references (NaN sign/payload aside)',
        'approximate_functions': 'special values, exact cases and errno rules; '
                                 'accuracy is measured by math-oracle-check.py',
        'host_compiler': False, 'host_linker': False, 'host_libm': False,
        'seconds': {'build': round(built - start, 1), 'run': round(ran - built, 1),
                    'check': round(checked - ran, 1)},
        'source_sha256': {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in SOURCES},
        'artifact_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in [executable, out / 'inputs.bin', out / 'results.bin']},
    }
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: Forth-only libm fixture, %d records, exact references and special-value/errno contract'
          % len(cases))
    print(out / 'report.json')
    print('Numerical validation command: python3 tests/gcc/math-oracle-check.py --production-output ' + str(out))


if __name__ == '__main__':
    main()
