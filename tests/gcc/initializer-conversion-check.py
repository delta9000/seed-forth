#!/usr/bin/env python3
"""Record-to-scalar initializer/conversion constraints retain their error codes."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def cases():
    for kind in ('struct', 'union'):
        record = f'{kind} A{{long x;}};'
        for target in ('_Bool', 'signed char', 'unsigned short', 'int',
                       'unsigned', 'long', 'unsigned long long', 'float',
                       'double', 'long *'):
            for name, declaration in (
                ('scalar', f'{target} b=a;'),
                ('braced-scalar', f'{target} b={{a}};'),
                ('array', f'{target} b[1]={{a}};'),
                ('struct-member', f'struct B{{{target} x;}} b={{a}};'),
                ('union-member', f'union B{{{target} x;}} b={{a}};'),
                ('nested-member', f'struct B{{{target} x[1];}} b={{{{a}}}};'),
            ):
                yield f'{kind}-{target}-{name}', record+f'void f({kind} A a){{{declaration}}}', 232
            for name, body in (
                ('assignment', f'void f({kind} A a){{{target} b;b=a;}}'),
                ('cast', f'void f({kind} A a){{({target})a;}}'),
                ('return', f'{target} f({kind} A a){{return a;}}'),
                ('argument', f'void h({target});void f({kind} A a){{h(a);}}'),
                ('sizeof-argument', f'void h({target});long f({kind} A a){{return sizeof(h(a));}}'),
            ):
                yield f'{kind}-{target}-{name}', record+body, 232
            for name, declaration in (
                ('static', f'static {target} b=a;'),
                ('static-array', f'static {target} b[1]={{a}};'),
                ('static-member', f'static struct B{{{target} x;}} b={{a}};'),
            ):
                yield f'{kind}-{target}-{name}', record+f'void f({kind} A a){{{declaration}}}', 240
        for target in ('_Bool', 'signed int', 'unsigned int', 'unsigned long'):
            for container in ('struct', 'union'):
                width = 1 if target == '_Bool' else 3
                field = f'{container} B{{{target} x:{width};}}'
                for source, prefix in (
                    ('a', ''), ('*p', f'{kind} A *p=&a;'),
                    ('h()', f'{kind} A h(void);'), ('1?a:a', ''),
                ):
                    yield f'{kind}-{target}-{container}-bitfield-{source}', record+f'void f({kind} A a){{{prefix}{field} b={{{source}}};}}', 232
                yield f'{kind}-{target}-{container}-static-bitfield', record+f'void f({kind} A a){{static {field} b={{a}};}}', 240
        for expression in ('a+1', 'a==a', '+a', '-a', '!a', 'a&&1', 'a?1:0', '1?a:1', 'a++'):
            yield f'{kind}-expression-{expression}', record+f'void f({kind} A a){{{expression};}}', 232


def compile_case(root, source, output):
    return subprocess.run(['python3', str(root/'tools/gcc-direct-cc.py'),
                           '-c', str(source), '-o', str(output)],
                          capture_output=True, timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, help='Optional pristine pre-long-double source tree')
    args = parser.parse_args()
    count = 0
    with tempfile.TemporaryDirectory(prefix='initializer-conversion-', dir=ROOT/'build-out') as tmp:
        work = Path(tmp)
        def check(case):
            index, (name, body, code) = case
            directory = work/str(index)
            directory.mkdir()
            source = directory/'case.c'
            output = directory/'case.o'
            source.write_text(body+'\n')
            if args.baseline:
                result = compile_case(args.baseline, source, output)
                assert result.returncode == code, (name, 'baseline', code, result.returncode, result.stderr)
            for existing in (False, True):
                output.unlink(missing_ok=True)
                sentinel = b'previous-valid-object\x00\xff'
                if existing:
                    output.write_bytes(sentinel)
                result = compile_case(ROOT, source, output)
                assert result.returncode == code, (name, code, result.returncode, result.stderr)
                assert f'error {code}'.encode() in result.stderr, (name, result.stderr)
                assert output.read_bytes() == sentinel if existing else not output.exists(), name
            return 1

        with ThreadPoolExecutor(max_workers=4) as pool:
            count = sum(pool.map(check, enumerate(cases())))
    print(f'PASS: {count} struct/union initializer and scalar conversion rejections retain exact codes and preserve outputs'
          + ('; all codes match the pre-long-double tree' if args.baseline else ''))


if __name__ == '__main__':
    main()
