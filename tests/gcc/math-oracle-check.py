#!/usr/bin/env python3
"""Independent host/Decimal oracles; no results are production build inputs."""
from decimal import Decimal, localcontext
from pathlib import Path
import argparse
import ctypes
import hashlib
import json
import math
import random
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ['runtime/gcc-seed/math.c', 'runtime/gcc-seed/include/math.h',
           'tests/gcc/math-production.c', 'tests/gcc/math-oracle-check.py']
BUDGET = 2.0**-44
MIN_NORMAL = float.fromhex('0x1p-1022')
MIN_SUBNORMAL = float.fromhex('0x1p-1074')


def bits(number):
    return struct.unpack('<Q', struct.pack('<d', number))[0]


def number(value):
    return struct.unpack('<d', struct.pack('<Q', value))[0]


def run(command):
    result = subprocess.run(list(map(str, command)), capture_output=True, timeout=120)
    assert result.returncode == 0, (command, result.returncode, result.stdout, result.stderr)
    return result.stdout


def constants(precision):
    with localcontext() as context:
        context.prec = precision
        two = Decimal(2)
        ln2 = two.ln()
        high = number(bits(float(ln2)) & ~((1 << 21)-1))
        values = {'SEED_LN2_HI': high,
                  'SEED_LN2_LO': float(ln2-Decimal.from_float(high)),
                  'SEED_INV_LN2': float(1/ln2),
                  'overflow_boundary': float((two**1024-two**971).ln()),
                  'zero_boundary': float(-1075*ln2)}
        # Widened reduction radius includes floating reduction error.
        radius = ln2 / 2 + Decimal(2)**-40
        tail_exp = radius**19 / Decimal(math.factorial(19)) * radius.exp()
        z = Decimal(1)/5
        tail_log = 2*z**35/(35*(1-z*z))
        assert tail_exp < Decimal('2.1e-26')
        assert tail_log < Decimal('2.1e-26')
        assert Decimal.from_float(values['overflow_boundary']) < (two**1024-two**971).ln()
        assert Decimal.from_float(math.nextafter(values['overflow_boundary'], math.inf)) > (two**1024).ln()
        assert Decimal.from_float(values['zero_boundary']) < -1075*ln2
        assert Decimal.from_float(math.nextafter(values['zero_boundary'], math.inf)) > -1075*ln2
        return {k: {'value': repr(v), 'bits': '%016x' % bits(v)} for k,v in values.items()}, {'exp': str(tail_exp), 'log': str(tail_log)}


def expected_errno(op, x, output):
    if math.isnan(x):
        return 123
    if op == 0:
        if x == 0.0: return 34
        if x < 0.0: return 33
    if op == 1 and math.isfinite(x) and (output < MIN_NORMAL or math.isinf(output)):
        return 34
    return 123


def host_reference(op, x, count=1):
    if op == 0:
        if x == 0.0: return -math.inf
        if x < 0.0: return math.nan
        return math.log(x)
    if op == 1:
        try: return math.exp(x)
        except OverflowError: return math.inf
    return math.exp(math.log(x)/count)


def check_value(op, x, count, actual, expected, actual_errno=None):
    if actual_errno is not None:
        assert actual_errno == expected_errno(op, x, actual), (op, x, actual, actual_errno)
    if math.isnan(expected):
        assert math.isnan(actual), (op, x, actual, expected)
        return 0.0
    if math.isinf(expected) or expected == 0.0:
        assert bits(actual) == bits(expected), (op, x, actual, expected)
        return 0.0
    assert math.isfinite(actual), (op, x, actual, expected)
    # Subnormal exp output uses an absolute 2-ulp validation budget.
    limit = 2*MIN_SUBNORMAL if op == 1 and abs(expected) < MIN_NORMAL else BUDGET*abs(expected)
    assert abs(actual-expected) <= limit, (op, x, count, actual, expected, limit)
    return abs(actual-expected)/math.ulp(expected)


def check_records(data, decimal_stride=113):
    worst = {str(i): {'ulp': 0.0} for i in range(3)}
    counts = [0,0,0]
    decimal_checks = 0
    boundary_disagreements = []
    # Decimal does not copy the implemented reduced series or constants.
    with localcontext() as context:
        context.prec = 100
        for index, line in enumerate(data.decode().splitlines()):
            op, xb, n, yb, actual_errno = line.split()
            op, count, actual_errno = int(op), int(n), int(actual_errno)
            x, y = number(int(xb,16)), number(int(yb,16))
            expected = host_reference(op, x, count)
            error = check_value(op, x, count, y, expected, actual_errno)
            counts[op] += 1
            if error > worst[str(op)]['ulp']:
                worst[str(op)] = {'ulp': error, 'x_bits': xb, 'count': count,
                                  'actual_bits': yb, 'host_bits': '%016x' % bits(expected)}
            if math.isfinite(x) and ((op != 0 and abs(x) <= 745.14) or (op != 1 and x > 0)) and (index % decimal_stride == 0 or op == 2):
                d = Decimal.from_float(x)
                if op == 0: exact = d.ln()
                elif op == 1: exact = d.exp()
                else: exact = (d.ln()/count).exp()
                check_value(op, x, count, y, float(exact))
                decimal_checks += 1
            if op == 2:
                boundary = round(expected)
                if abs(expected-boundary) <= 4*math.ulp(expected) and (y > boundary) != (expected > boundary):
                    boundary_disagreements.append({'x': x, 'count': count, 'boundary': boundary,
                                                   'seed_bits': yb, 'host_bits': '%016x' % bits(expected)})
    return {'counts': counts, 'decimal_checks': decimal_checks, 'worst_against_host': worst,
            'near_integer_greater_than_disagreement_count': len(boundary_disagreements),
            'near_integer_greater_than_disagreement_examples': boundary_disagreements[:12]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--production-output', type=Path)
    args = parser.parse_args()
    (ROOT/'build-out').mkdir(exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix='math-oracle-', dir=ROOT/'build-out'))
    first, remainders = constants(100)
    second, unused = constants(180)
    assert first == second
    source = (ROOT/SOURCES[0]).read_text()
    for name, entry in first.items():
        value = entry['value']
        if name.startswith('SEED_'):
            literal = re.search(r'^#define '+name+r' (\S+)$', source, re.M).group(1)
            assert bits(float(literal)) == int(entry['bits'],16)
    assert bits(float('7.09782712893383973096e+02')) == int(first['overflow_boundary']['bits'],16)
    assert bits(float('-7.45133219101941222107e+02')) == int(first['zero_boundary']['bits'],16)
    report = {'proof': 'HOST AND DECIMAL ORACLES ONLY; not a production reconstruction',
              'relative_validation_budget': BUDGET, 'constants': first, 'ideal_series_tail_bounds': remainders,
              'source_sha256': {n: hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in SOURCES}, 'levels': {}}
    compiler = shutil.which('gcc')
    assert compiler, 'host GCC required only for this explicitly oracle-only test'
    report['host_compiler'] = run([compiler,'--version']).decode().splitlines()[0]
    outputs = []
    for level in ['-O0','-O2']:
        flags = [compiler, '-std=c90', '-pedantic', '-Wall','-Wextra','-Werror', '-fno-builtin',
                 '-ffp-contract=off',level,'-I',ROOT/'runtime/gcc-seed/include']
        executable = out/('host-'+level[1:])
        run(flags+[ROOT/'runtime/gcc-seed/math.c',ROOT/'tests/gcc/math-production.c','-o',executable])
        data = run([executable])
        (out/(executable.name+'.txt')).write_bytes(data)
        summary = check_records(data)
        shared = out/('host-'+level[1:]+'.so')
        run(flags+['-shared','-fPIC','-Dexp=seed_exp','-Dlog=seed_log', ROOT/'runtime/gcc-seed/math.c','-o',shared])
        library = ctypes.CDLL(str(shared),use_errno=True)
        random_source = random.Random(0x90404)
        summary['random_counts'] = {'log':100000,'exp':100000}
        summary['random_worst_ulp'] = {}
        for name in ['log','exp']:
            function = getattr(library,'seed_'+name)
            function.argtypes = [ctypes.c_double]
            function.restype = ctypes.c_double
            maximum = 0.0
            for i in range(100000):
                x = number(random_source.randrange(1,0x7ff0000000000000)) if name=='log' else random_source.uniform(-745.2,709.9)
                ctypes.set_errno(123)
                y = function(x)
                op = 0 if name=='log' else 1
                maximum = max(maximum,check_value(op,x,1,y,host_reference(op,x),ctypes.get_errno()))
            summary['random_worst_ulp'][name] = maximum
        report['levels'][level] = summary
        outputs.append(data)
    assert outputs[0] == outputs[1], 'optimization changed implementation results'
    report['same_bits_and_errno_at_O0_O2'] = True
    if args.production_output:
        data = args.production_output.read_bytes()
        assert data == outputs[0], 'Forth and host builds of same implementation disagree'
        report['production_comparison'] = check_records(data)
        report['production_output_sha256'] = hashlib.sha256(data).hexdigest()
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: exp/log host and Decimal reference checks; Forth reconstruction is separate')
    print(out/'report.json')


if __name__ == '__main__':
    main()
