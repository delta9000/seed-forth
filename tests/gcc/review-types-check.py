#!/usr/bin/env python3
"""Independent metadata/layout and forbidden-value tests; host tools are oracles."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / 'tests/gcc'
INCLUDES = [TESTS, ROOT / 'runtime/gcc-seed/include']
MODES = ('sysv-compile.sh', 'sysv-object-compile.sh')
REJECTIONS = {
    'floating-parameter-definition': (232, 'int f(double x){return 0;}'),
    'floating-return-definition': (232, 'float f(void){return 0;}'),
    'aggregate-parameter-definition': (232, 'struct S{double x;}; int f(struct S s){return 0;}'),
    'aggregate-return-definition': (232, 'struct S{double x;}; struct S f(void){struct S s; return s;}'),
    'floating-direct-call': (232, 'int f(double); int main(void){return f(1);}'),
    'floating-return-call': (232, 'float f(void); int main(void){f();return 0;}'),
    'aggregate-direct-call': (232, 'struct S{double x;}; int f(struct S); int main(void){struct S s;return f(s);}'),
    'aggregate-return-call': (232, 'struct S{double x;}; struct S f(void); int main(void){f();return 0;}'),
    'floating-pointer-call': (232, 'int main(void){int (*f)(double);f=0;return f(1);}'),
    'aggregate-pointer-call': (232, 'struct S{double x;}; int main(void){int (*f)(struct S);struct S s;f=0;return f(s);}'),
    'floating-local-read': (232, 'int main(void){float f;return f;}'),
    'floating-discarded-read': (232, 'int main(void){float d;d;return 0;}'),
    'floating-local-write': (232, 'int main(void){float d;d=1;return 0;}'),
    'floating-local-initializer': (232, 'int main(void){long double d=1;return 0;}'),
    'floating-global-read': (232, 'float d; int main(void){return d;}'),
    'floating-global-write': (232, 'float f; int main(void){f=1;return 0;}'),
    'floating-dereference-read': (232, 'int f(long double *p){return *p;}'),
    'floating-dereference-write': (232, 'int f(float *p){*p=1;return 0;}'),
    'floating-field-read': (232, 'struct S{float d;}; int f(struct S *s){return s->d;}'),
    'floating-field-write': (232, 'struct S{long double d;}; int f(struct S *s){s->d=1;return 0;}'),
    'floating-cast': (232, 'int main(void){return (int)(float)1;}'),
    'floating-postincrement': (232, 'int f(double *p){(*p)++;return 0;}'),
    'floating-comparison': (232, 'int f(float *p){return *p==0;}'),
    'floating-static-scalar': (232, 'static double d=0; int main(void){return sizeof(d)!=8;}'),
    'floating-static-local': (232, 'int main(void){static long double d=0;return sizeof(d)!=16;}'),
    'floating-static-array': (232, 'float f[2]={0,0}; int main(void){return sizeof(f)!=8;}'),
    'floating-static-field': (232, 'struct S{double d;}; struct S s={0}; int main(void){return sizeof(s)!=8;}'),
    'floating-typed-constant': (240, 'enum E{n=(int)(double)1}; int main(void){return 0;}'),
    'floating-va-arg': (247, '#include <stdarg.h>\nint f(int n,...){va_list a;va_start(a,n);va_arg(a,float);return 0;}'),
}


def run(args, expected=0):
    result = subprocess.run(args, capture_output=True, timeout=60)
    if result.returncode != expected:
        raise RuntimeError(f'{args}: exit {result.returncode}, wanted {expected}\n'
                           + result.stdout.decode(errors='replace')
                           + result.stderr.decode(errors='replace'))
    return result


def main():
    cc = shutil.which('gcc')
    if not cc:
        raise SystemExit('SKIP: gcc is required only for the independent host oracle')
    inputs = [ROOT / 'seed-forth', ROOT / '010-lib.fth'] + [
        path for path in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))
        if path.name not in ('120-cc-main.fth', '140-cc-link.fth')]
    inputs += [TESTS / name for name in MODES]
    inputs += sorted(TESTS.glob('review-types-*'))
    inputs += [ROOT / 'runtime/gcc-seed/include/stdarg.h']
    inputs = [path for path in inputs if path.suffix not in ('.json', '.md')]
    hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in inputs}
    with tempfile.TemporaryDirectory(prefix='review-types.') as directory:
        work = Path(directory)
        target = work / 'target.o'
        run([TESTS / MODES[1], TESTS / 'review-types-fixture.c', target, *INCLUDES])
        text = (TESTS / 'review-types-fixture.c').read_text().replace(
            '#include "review-types-fixture.h"', (TESTS / 'review-types-fixture.h').read_text())
        reference = work / 'reference.c'
        reference.write_text(text.replace('review_types_', 'reference_types_'))
        for optimization in ('-O0', '-O2'):
            oracle = work / ('oracle' + optimization[1:])
            run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', optimization,
                 '-fno-pie', '-no-pie', '-Wl,-z,noexecstack', '-I'+str(TESTS),
                 TESTS / 'review-types-oracle.c', reference, target, '-o', oracle])
            print(run([oracle]).stdout.decode().strip(), optimization, flush=True)
        symbols = run(['readelf', '-sW', target]).stdout.decode()
        sizes = {parts[7]: int(parts[2]) for line in symbols.splitlines()
                 if len(parts := line.split()) == 8 and parts[3] == 'OBJECT'}
        expected_sizes = {'review_types_floats': 12, 'review_types_doubles': 24,
                          'review_types_long_doubles': 48, 'review_types_mixed': 96,
                          'review_types_nested': 128, 'review_types_union': 16}
        assert {name: sizes.get(name) for name in expected_sizes} == expected_sizes
        relocations = run(['readelf', '-rW', target]).stdout.decode()
        assert 'unevaluated' not in relocations, 'sizeof(call) emitted a call relocation'
        sentinel = b'previous valid artifact\n'
        for name, (code, source) in REJECTIONS.items():
            path = work / (name + '.c')
            path.write_text(source + '\n')
            for mode in MODES:
                output = work / (name + '-' + mode)
                for existing in (False, True):
                    if existing:
                        output.write_bytes(sentinel)
                    result = run([TESTS / mode, path, output, *INCLUDES], expected=code)
                    diagnostic = result.stderr.decode()
                    assert not result.stdout, (name, mode, result.stdout)
                    assert re.search(r'cc: line \d+: error ' + str(code) + r'\b', diagnostic), diagnostic
                    if code == 247:
                        assert 'varargs: ' in diagnostic, diagnostic
                    if existing:
                        assert output.read_bytes() == sentinel, (name, mode, 'replaced prior output')
                    else:
                        assert not output.exists(), (name, mode, 'published rejected output')
            print('PASS:', name, 'rejects with', code, 'in ELF/object modes; output preserved', flush=True)
        current = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                   for path in inputs}
        if current != hashes:
            raise RuntimeError('compiler or review sources changed during review; rerun stable sources')
        print(json.dumps({'source_sha256': hashes, 'layout_comparisons': 31,
                          'rejection_cases': len(REJECTIONS),
                          'publication_checks': 4*len(REJECTIONS)}, sort_keys=True))


if __name__ == '__main__':
    main()
