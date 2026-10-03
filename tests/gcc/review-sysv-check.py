#!/usr/bin/env python3
"""Independent ABI and fail-closed review; host tools are test oracles only."""
from pathlib import Path
import hashlib
import json
import re
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
    inputs = [ROOT / 'seed-forth', ROOT / '010-lib.fth'] + [
        p for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))
        if p.name not in ('120-cc-main.fth', '140-cc-link.fth')]
    inputs += [ROOT / 'tests/gcc/sysv-compile.sh',
               ROOT / 'tests/gcc/sysv-object-compile.sh']
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


        # Repeat all ABI instrumentation against the actual ET_REL adapter.
        # Rename target symbols so the host can retain independent references.
        fixture = (ROOT / 'tests/gcc/review-sysv-fixture.c').read_text().split('/* Pointer export')[0]
        object_source = work / 'object-target.c'
        object_source.write_text(fixture.replace('review_', 'seed_'))
        obj = work / 'target.o'
        run([str(ROOT / 'tests/gcc/sysv-object-compile.sh'), str(object_source), str(obj)])
        prototypes = []
        for match in re.finditer(r'(?m)^(?:long|signed char|unsigned char|short|unsigned short|int|unsigned int) (review_\w+)\([^;{}]*\) \{', fixture):
            prototype = match.group(0)[:-2]
            prototypes.append(prototype.replace(match.group(1), match.group(1).replace('review_', 'seed_'), 1)+';')
        names = ['zero', 'six', 'seven', 'eight', 'twelve', 'recursion', 'operands',
                 'narrow', 'return_char', 'return_uchar', 'return_short', 'return_ushort',
                 'return_int', 'return_uint', 'callback', 'call_narrow', 'call_variadic', 'control']
        assert len(prototypes) == len(names)
        exports = '\n'.join(prototypes)+'\nstatic long review_object_lookup(long index) { switch(index) {'
        exports += ''.join(f'case {i}: return (long)seed_{name};' for i, name in enumerate(names))
        exports += 'default: return 0; } }\n'
        (work / 'review-sysv-object-exports.h').write_text(exports)
        for optimization in ('-O0', '-O2'):
            oracle = work / ('object-oracle'+optimization[1:])
            run([cc, '-std=c99', '-Wall', '-Wextra', '-Werror', optimization,
                 '-fPIE', '-pie', '-Wl,-z,noexecstack', '-DREVIEW_OBJECT_ORACLE',
                 '-I'+str(work), str(ROOT / 'tests/gcc/review-sysv-oracle.c'),
                 str(ROOT / 'tests/gcc/review-sysv-oracle.S'), str(obj), '-o', str(oracle)])
            print(run([str(oracle)]).stdout.decode().strip(), 'ET_REL', optimization)

        valid = {
            'oldstyle-promoted-parameters': '''
                long f(int,int);
                long f(a,b) signed char a; unsigned short b; { return a+b; }
                int main(void) { return f(255,65535)!=65534; }''',
            'oldstyle-implicit-int': '''
                long f();
                long f(a,b) long b; { return a+b; }
                int main(void) { return f(12,30L)!=42; }''',
            'oldstyle-eight-arguments': '''
                long f();
                long f(a,b,c,d,e,f,g,h)
                signed char a; unsigned char b; short c; unsigned short d;
                int e; unsigned int f; long g; unsigned long h;
                { return a!=-128 || b!=255 || c!=-32768 || d!=65535
                    || e!=(-2147483647-1) || f!=4294967295U
                    || g!=-4294967297L || h!=18446744073709551615UL; }
                int main(void) { return f(128,255,32768,65535,(-2147483647-1),
                    4294967295U,-4294967297L,18446744073709551615UL); }''',
            'prototype-survives-unspecified': '''
                long f(long);
                long f();
                long f(long x) { return x; }
                int main(void) { return f(42L)!=42; }''',
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
            'floating-and-aggregate-metadata': '''
                struct S { char c; long double ld; double d; };
                double external_double(void); struct S external_struct(void);
                int main(void) {
                    long (*floating)(double); long (*aggregate)(struct S);
                    float f; double d; long double ld; struct S s;
                    return sizeof(floating)!=8 || sizeof(aggregate)!=8
                        || sizeof(f)!=4 || sizeof(d)!=8 || sizeof(ld)!=16
                        || sizeof(s)!=48 || sizeof(external_double())!=8
                        || sizeof(external_struct())!=48;
                }''',
            'floating-pointer-arithmetic': '''
                int main(void) {
                    float f[3]; double d[3]; long double ld[3];
                    float *fp; double *dp; long double *lp;
                    fp=&f[0]; dp=&d[0]; lp=&ld[0];
                    return (char *)(fp+2)-(char *)fp!=8
                        || (char *)(dp+2)-(char *)dp!=16
                        || (char *)(lp+2)-(char *)lp!=32
                        || sizeof(*lp)!=16;
                }''',
        }
        args = ','.join(f'long a{i}' for i in range(64))
        values = ','.join(str(i+1) for i in range(64))
        weighted = '+'.join(f'a{i}*{i+1}' for i in range(64))
        total = sum(i*i for i in range(1,65))
        valid['64-arguments'] = f'long f({args}) {{ return {weighted}; }} int main(void) {{ return f({values})!={total}; }}'
        rejections = {
            'void-after-parameter': (233, 'int f(int a,void){return a;} int main(void){return 0;}'),
            'duplicate-typed-parameter': (233, 'int f(int a,int a){return a;} int main(void){return 0;}'),
            'oldstyle-duplicate-parameter': (233, 'int f(a,a) int a; {return a;} int main(void){return 0;}'),
            'oldstyle-unknown-declaration': (233, 'int f(a) int b; {return a;} int main(void){return 0;}'),
            'oldstyle-duplicate-declaration': (233, 'int f(a) int a; int a; {return a;} int main(void){return 0;}'),
            'unspecified-narrow-prototype': (237, 'int f(); int f(char x){return x;} int main(void){return 0;}'),
            'prototype-survives-for-arity': (235, 'long f(long); long f(); long f(long x){return x;} int main(void){return f();}'),
            'function-parameter-declarator': (233, 'int f(int cb(int)){return 0;} int main(void){return 0;}'),
            '65-parameters': (234, 'long f(' + ','.join(f'long a{i}' for i in range(65)) + '); int main(void){return 0;}'),
            '65-call-arguments': (234, 'long f(long x,...); int main(void){return f(' + ','.join('1' for _ in range(65)) + ');}'),
            'pointer-call-too-few': (235, 'long f(long x){return x;} int main(void){long (*p)(long); p=f; return p();}'),
            'pointer-call-too-many': (235, 'long f(long x){return x;} int main(void){long (*p)(long); p=f; return (*p)(1,2);}'),
            'conflicting-callback-param': (237, 'long f(long (*p)(long)); long f(long (*p)(int)){return 0;} int main(void){return 0;}'),
            'conflicting-param-width': (237, 'long f(short); long f(int x){return x;} int main(void){return 0;}'),
            'conflicting-param-signedness': (237, 'long f(unsigned int); long f(int x){return x;} int main(void){return 0;}'),
            'conflicting-varargs': (237, 'long f(long,...); long f(long x){return x;} int main(void){return 0;}'),
            'conflicting-struct-pointer': (237, 'struct A{int x;}; struct B{int x;}; long f(struct A*); long f(struct B*x){return 0;} int main(void){return 0;}'),
            'floating-function-pointer-call': (232, 'int main(void){long (*p)(double); p=0; return p(1);}'),
            'aggregate-function-pointer-call': (232, 'struct S{int x;}; int main(void){long (*p)(struct S); struct S s; p=0; return p(s);}'),
            'floating-local-value': (232, 'int main(void){float d; return d;}'),
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
            output = work / name
            run([str(ROOT / 'tests/gcc/sysv-compile.sh'), str(path), str(output)], expected=code)
            if output.exists():
                raise RuntimeError(f'rejected {name} published an executable')
            results.append({'name':name,'status':'REJECT','code':code})
            print('PASS:',name,'rejects with',code)
        current = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
        if hashes != current:
            raise RuntimeError('compiler changed during review; rerun against stable sources')
        print(json.dumps({'compiler_inputs_sha256':hashes,'cases':results},sort_keys=True))


if __name__ == '__main__':
    main()
