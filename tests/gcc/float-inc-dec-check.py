#!/usr/bin/env python3
"""Floating ++/-- lvalues and expression results, compared with host GCC.

Print raw object bytes to observe signed zero, binary32 rounding, both
expression values and stores, without depending on decimal formatting.
Each expression modifies one object once; index/pointer side effects are
sequenced separately from observations. Host GCC is an independent oracle.
"""
from pathlib import Path
import resource
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CC = [sys.executable, ROOT / 'tools/gcc-direct-cc.py']


def run(command, expected=0):
    result = subprocess.run([str(x) for x in command], capture_output=True, timeout=300)
    if result.returncode != expected:
        raise RuntimeError(f'{command}: exit {result.returncode}, expected {expected}\n'
                           + result.stdout.decode(errors='replace')
                           + result.stderr.decode(errors='replace'))
    return result


def fixture():
    lines = ['#include <stdio.h>',
             'float gf; double gd;',
             'struct cells { unsigned before; float f; double d; unsigned after; };',
             'void dump(void *p, int n) { unsigned char *b = p; int j;',
             '  for (j = 0; j < n; j++) printf("%02x", (unsigned)b[j]);',
             '  printf(" "); }',
             'int main(void) {',
             '  float f, af[3], rf, *qf = &af[1];',
             '  double d, ad[3], rd, z, *qd = &ad[1];',
             '  struct cells s, *p = &s; int k;',
             '  s.before = 123; s.after = 456;',
             '  af[0] = 17.0f; af[2] = 19.0f; ad[0] = 23.0; ad[2] = 29.0;',
             # The reported original failure, as a standalone statement.
             '  d = 0.0; d++; dump(&d, sizeof d); printf("\\n");']
    cases = 0
    for tag, boundary in [('f', '16777216.0f'), ('d', '9007199254740992.0')]:
        for target in [tag, 'g' + tag, 's.' + tag, 'p->' + tag,
                       'a' + tag + '[k++]', '*q' + tag, '(*q' + tag + '++)']:
            # Every lvalue shape gets all four operations at both signs,
            # signed zero, and the precision boundary where +1 rounds away.
            for start in ['0.25', '-2.75', '-0.0', boundary]:
                for op in ['post++', 'pre++', 'post--', 'pre--']:
                    base = target.replace('k++', '1').replace('q' + tag + '++', 'q' + tag)
                    operand = f'({target})' if target.startswith('*') and op.startswith('post') else target
                    expr = operand + op[4:] if op.startswith('post') else op[3:] + operand
                    observed = 'a' + tag + '[1]' if 'q' + tag + '++' in target else base
                    lines += [f'  k = 1; q{tag} = &a{tag}[1]; {base} = {start};',
                              f'  r{tag} = {expr};',
                              f'  dump(&r{tag}, sizeof r{tag}); dump(&({observed}), sizeof({observed}));',
                              f'  printf("%d %d\\n", k, (int)(q{tag} - &a{tag}[1]));',
                              f'  k = 1; q{tag} = &a{tag}[1]; {base} = {start};',
                              f'  z = 2.0 + ({expr}) * 3.0;',
                              f'  dump(&z, sizeof z); dump(&({observed}), sizeof({observed}));',
                              f'  printf("%d %d\\n", k, (int)(q{tag} - &a{tag}[1]));']
                    cases += 1
    lines += ['  dump(af, sizeof af); dump(ad, sizeof ad);',
              '  printf("%u %u\\n", s.before, s.after); return 0; }']
    return '\n'.join(lines) + '\n', cases


def main():
    resource.setrlimit(resource.RLIMIT_AS, (1024 ** 3, 1024 ** 3))
    with tempfile.TemporaryDirectory(prefix='float-inc-dec-') as directory:
        work = Path(directory)
        source = work / 'main.c'
        text, cases = fixture()
        source.write_text(text)
        run(CC + ['-static', source, '-o', work / 'forth'])
        actual = run([work / 'forth']).stdout
        if len(actual.splitlines()) != cases * 2 + 2:
            raise RuntimeError('Forth program did not complete')
        for opt in ['-O0', '-O2']:
            run(['gcc', '-std=c99', '-Wall', '-Wextra', '-Werror', opt,
                 '-fno-fast-math', '-ffp-contract=off', '-static', source, '-o', work / 'host'])
            expected = run([work / 'host']).stdout
            if actual != expected:
                for n, (a, b) in enumerate(zip(actual.splitlines(), expected.splitlines()), 1):
                    if a != b:
                        raise RuntimeError(f'{opt}: line {n}: Forth {a!r}, GCC {b!r}')
                raise RuntimeError(f'{opt}: output lengths differ')
        for expr in ['x++', '++x', 'x--', '--x']:
            source.write_text(f'long double x; void f(void) {{ {expr}; }}\n')
            output = work / 'reject.o'
            run(CC + ['-c', source, '-o', output])
        print(f'PASS: {cases} floating increment/decrement cases, direct and larger expressions, '
              'match GCC -O0/-O2; four long double forms compile')


if __name__ == '__main__':
    main()
