#!/usr/bin/env python3
"""Independent ABI and fail-closed review; host tools are test oracles only."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(args, expected=0, **kwargs):
    result = subprocess.run(args, capture_output=True, **kwargs)
    if result.returncode != expected:
        raise RuntimeError(f"{args}: exit {result.returncode}, wanted {expected}\n"
                           f"{result.stdout.decode(errors='replace')}"
                           f"{result.stderr.decode(errors='replace')}")
    return result


def compile_seed(source, target):
    return run([str(ROOT / 'tests/gcc/sysv-compile.sh'), str(source), str(target)])


def main():
    cc = shutil.which('gcc')
    if not cc:
        raise SystemExit('SKIP: gcc needed only for independent ABI oracle')
    inputs = sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    with tempfile.TemporaryDirectory(prefix='review-sysv.') as temp:
        work = Path(temp)
        target = work / 'target'
        compile_seed(ROOT / 'tests/gcc/review-sysv-fixture.c', target)
        for optimization in ('-O0', '-O2'):
            oracle = work / ('oracle' + optimization[1:])
            run([cc, '-std=c99', '-Wall', '-Wextra', '-Werror', optimization,
                 '-fPIE', '-pie', str(ROOT / 'tests/gcc/review-sysv-oracle.c'),
                 str(ROOT / 'tests/gcc/review-sysv-oracle.S'), '-o', str(oracle)])
            print(run([str(oracle), str(target)]).stdout.decode().strip(), optimization)

        valid = {
            'typedef-function-pointer-return': '''
                typedef long (*F)(long);
                long add(long x) { return x+3; }
                F factory(void) { return add; }
                int main(void) { F f; f=factory(); return f(39)!=42; }''',
            'array-pointer-prototype': '''
                long sum(int *p, long n);
                long sum(int p[], long n) { if (n==0) return 0; return p[n-1]+sum(p,n-1); }
                int main(void) { int a[3]; a[0]=4; a[1]=8; a[2]=16; return sum(a,3)!=28; }''',
            'compatible-callback-prototype': '''
                typedef long (*F)(long);
                long call(F,long);
                long call(long (*f)(long),long x) { return f(x); }
                long plus(long x) { return x+3; }
                int main(void) { return call(plus,39)!=42; }''',
            'struct-pointer-prototype': '''
                struct S { long x; };
                long f(struct S *p); long f(struct S *p) { return p->x; }
                int main(void) { struct S s; s.x=42; return f(&s)!=42; }''',
        }
        args = ','.join(f'long a{i}' for i in range(64))
        values = ','.join(str(i+1) for i in range(64))
        weighted = '+'.join(f'a{i}*{i+1}' for i in range(64))
        total = sum(i*i for i in range(1,65))
        valid['64-arguments'] = f'long f({args}) {{ return {weighted}; }} int main(void) {{ return f({values})!={total}; }}'
        rejections = {
            '65-parameters': (234, 'long f(' + ','.join(f'long a{i}' for i in range(65)) + '); int main(void){return 0;}'),
            '65-call-arguments': (234, 'long f(long x,...); int main(void){return f(' + ','.join('1' for _ in range(65)) + ');}'),
            'pointer-call-too-few': (235, 'long f(long x){return x;} int main(void){long (*p)(long); p=f; return p();}'),
            'pointer-call-too-many': (235, 'long f(long x){return x;} int main(void){long (*p)(long); p=f; return (*p)(1,2);}'),
            'conflicting-callback-param': (237, 'long f(long (*p)(long)); long f(long (*p)(int)){return 0;} int main(void){return 0;}'),
            'conflicting-param-width': (237, 'long f(short); long f(int x){return x;} int main(void){return 0;}'),
            'conflicting-param-signedness': (237, 'long f(unsigned int); long f(int x){return x;} int main(void){return 0;}'),
            'conflicting-varargs': (237, 'long f(long,...); long f(long x){return x;} int main(void){return 0;}'),
            'conflicting-struct-pointer': (237, 'struct A{int x;}; struct B{int x;}; long f(struct A*); long f(struct B*x){return 0;} int main(void){return 0;}'),
            'floating-function-pointer': (214, 'int main(void){long (*p)(double); return 0;}'),
            'aggregate-function-pointer': (232, 'struct S{int x;}; int main(void){long (*p)(struct S); return 0;}'),
            'floating-local': (214, 'int main(void){double d; return 0;}'),
        }
        results = []
        for name, source in valid.items():
            path = work / (name+'.c'); path.write_text(source+'\n')
            exe = work / name
            compile_seed(path,exe)
            run([str(exe)])
            results.append({'name':name,'status':'PASS'})
            print('PASS:',name)
        for name, (code, source) in rejections.items():
            path = work / (name+'.c'); path.write_text(source+'\n')
            run([str(ROOT / 'tests/gcc/sysv-compile.sh'), str(path), str(work/name)], expected=code)
            results.append({'name':name,'status':'REJECT','code':code})
            print('PASS:',name,'rejects with',code)
        current = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        if hashes != current:
            raise RuntimeError('compiler changed during review; rerun against stable sources')
        print(json.dumps({'compiler_inputs_sha256':hashes,'cases':results},sort_keys=True))


if __name__ == '__main__':
    main()
