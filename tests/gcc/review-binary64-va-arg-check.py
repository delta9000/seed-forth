#!/usr/bin/env python3
"""Independent, bounded SysV binary64 va_arg review. Host GCC is oracle only."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(arguments, status=0):
    result = subprocess.run([str(a) for a in arguments], capture_output=True,
                            text=True, timeout=120)
    assert result.returncode == status, (arguments, result.returncode,
                                         result.stdout, result.stderr)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline-varargs', type=Path)
    args = parser.parse_args()
    (ROOT / 'build-out').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='review-binary64-', dir=ROOT / 'build-out'))
    compiler = ROOT / 'tests/gcc/sysv-object-compile.sh'
    sources = [ROOT / 'seed-forth', ROOT / '010-lib.fth', compiler,
               *sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),
               ROOT / 'runtime/gcc-seed/include/stdarg.h', Path(__file__),
               ROOT / 'tests/gcc/review-binary64-va-arg.c',
               ROOT / 'tests/gcc/review-binary64-va-arg-oracle.c']
    hashes = {str(p.relative_to(ROOT)): sha(p) for p in sources}
    obj = work / 'review.o'
    run([compiler, ROOT / 'tests/gcc/review-binary64-va-arg.c', obj,
         ROOT / 'runtime/gcc-seed/include'])
    executions = []
    for opt in ('-O0', '-O2'):
        exe = work / ('host' + opt)
        run(['gcc', '-std=c99', opt, '-Wall', '-Wextra', '-Werror', '-fno-pie',
             '-no-pie', ROOT / 'tests/gcc/review-binary64-va-arg-oracle.c', obj, '-o', exe])
        result = run([exe])
        assert result.stdout.startswith('PASS: independent binary64 '), result.stdout
        executions.append({'optimization': opt, 'stdout': result.stdout,
                           'executable_sha256': sha(exe)})
    negatives = {
        'typedef-float': (247, 'typedef float F; void f(va_list a){va_arg(a,F);}'),
        'typedef-long-double': (249, 'typedef long double F; double f(va_list a){return va_arg(a,F);}'),
        'qualified-float': (247, 'void f(va_list a){va_arg(a,const float);}'),
        'narrow-char': (247, 'void f(va_list a){va_arg(a,char);}'),
        'narrow-short': (247, 'void f(va_list a){va_arg(a,short);}'),
        'void-result': (247, 'void f(va_list a){va_arg(a,void);}'),
        'array-result': (247, 'typedef double A[2]; void f(va_list a){va_arg(a,A);}'),
        # Records with floating members have no ABI class yet (131).
        'aggregate-result': (232, 'struct X {double x;}; void f(va_list a){va_arg(a,struct X);}'),
        'wrong-record': (246, 'struct X {unsigned int a,b;void *c,*d;}; void f(struct X *a){va_arg(a,double);}'),
        'integer-list': (246, 'void f(long a){va_arg(a,double);}'),
        # Long double retrieval and passing are data movement (long-double-check.py);
        # these cases convert the value, which needs x87 code.
        'named-extended': (249, 'double f(long double x,...){va_list a;va_start(a,x);return x;}'),
        'outbound-fixed-extended': (249, 'void g(long double);void f(double *x){g(*x);}'),
        'outbound-variadic-extended': (249, 'void g(int,...);void f(long double *x){g(0,(double)*x);}'),
        'pointer-to-list-array': (246, 'void f(va_list **list){va_arg(list,double);}'),
    }
    diagnostic_records = []
    for name, (status, body) in negatives.items():
        source = work / (name + '.c')
        source.write_text('#include <stdarg.h>\n' + body + '\n')
        output = work / (name + '.o')
        sentinel = b'existing output\x00\xff\n'
        output.write_bytes(sentinel)
        result = run([compiler, source, output, ROOT / 'runtime/gcc-seed/include'], status)
        assert not result.stdout and output.read_bytes() == sentinel
        assert re.fullmatch(r'(?:varargs: |long-double: |aggregate-abi: )?cc: line \d+: error ' + str(status) + r'\n', result.stderr), result.stderr
        diagnostic_records.append({'case': name, 'exit_status': status,
                                   'output_preserved': True, 'diagnostic': result.stderr})
    baseline = None
    if args.baseline_varargs:
        old = work / 'baseline'
        (old / 'tests/gcc').mkdir(parents=True)
        (old / 'runtime/gcc-seed/include').mkdir(parents=True)
        for source in [ROOT / 'seed-forth', ROOT / '010-lib.fth',
                       *sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))]:
            shutil.copy2(source, old / source.name)
        shutil.copy2(args.baseline_varargs, old / '126-cc-varargs.fth')
        shutil.copy2(compiler, old / 'tests/gcc/sysv-object-compile.sh')
        shutil.copy2(ROOT / 'runtime/gcc-seed/include/stdarg.h', old / 'runtime/gcc-seed/include/stdarg.h')
        output = work / 'baseline-pointer-to-list.o'
        output.write_bytes(b'baseline existing output')
        result = run([old / 'tests/gcc/sysv-object-compile.sh',
                      work / 'pointer-to-list-array.c', output,
                      old / 'runtime/gcc-seed/include'], 246)
        assert not result.stdout and output.read_bytes() == b'baseline existing output'
        assert re.fullmatch(r'varargs: cc: line \d+: error 246\n', result.stderr)
        baseline = {'scope': 'Only 126 replaced by frozen pre-increment source',
                    'baseline_varargs_sha256': sha(args.baseline_varargs),
                    'pointer_to_va_list_array_diagnostic': result.stderr,
                    'output_preserved': True}
    assert hashes == {str(p.relative_to(ROOT)): sha(p) for p in sources}
    report = {'scope': 'Independent binary64 incoming va_arg ABI and bounded type checks',
              'compiler_and_test_sha256': hashes, 'callee_object_sha256': sha(obj),
              'host_oracle_executions': executions, 'negative_cases': diagnostic_records,
              'preexisting_boundary_check': baseline,
              'covers': ['record-pointer list indirection and aliasing',
                         'list argument expression evaluated exactly once',
                         'va_list as struct-member array',
                         'qualified double extraction',
                         'record-pointer descriptors and double-pointer GP retrieval',
                         'independent GP/FP cursor changes and shared 8-byte overflow',
                         '8-byte stack alignment at each retrieval',
                         '14 interleaved GP/double values and 8 named GP arguments',
                         'host-created list after 8 named FP arguments',
                         'host-created list after host consumes a long double',
                         'cursor restore by va_copy and repeated traversal'],
              'limitations': ['No float/long-double argument emission or floating formatting',
                              'No Forth long-double retrieval',
                              'Pointer to va_list array remains rejected with 238']}
    (work / 'report.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print('PASS: independent binary64 ABI O0/O2 and', len(negatives), 'rejection/output-preservation cases')
    print(work / 'report.json')


if __name__ == '__main__':
    main()
