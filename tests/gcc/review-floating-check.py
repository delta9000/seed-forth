#!/usr/bin/env python3
"""Independent binary64 expression/return/storage and untouched-source review.

Forth supplies all reviewed target objects. Host C O0/O2 builds only the ABI
oracles. The literal worker's exact grammar has a separate review; this runner
uses no floating literals in its synthetic production-side fixture.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
HASHTAB_SHA='64dfaa8263d2b9c1737cb442824e0437b001dbafef92fc985c4431b5700ad802'
HEADER_SHA='4ea28b4fd9a06f5ac81e5f0f10e15dbafd39b262bfa1ef85618a7a2b2c1a859c'

def run(args,expected=0):
    result=subprocess.run([str(a) for a in args],capture_output=True,text=True)
    if result.returncode!=expected:
        raise RuntimeError(f'{args}: exit {result.returncode}, wanted {expected}\n'
                           f'{result.stdout}{result.stderr}')
    return result

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def compiler_hashes():
    paths=[ROOT/'seed-forth',ROOT/'010-lib.fth',ROOT/'tools/gcc-direct-cc.py']
    paths+=sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))
    paths+=sorted((ROOT/'runtime/gcc-seed/include').rglob('*.h'))
    paths += [ROOT/'tests/gcc/sysv-object-compile.sh']
    return {str(p.relative_to(ROOT)):sha(p) for p in paths}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--source-root',type=Path,default=ROOT/'build-out/direct-gcc-inputs/gcc-source')
    parser.add_argument('--report',type=Path)
    parser.add_argument('--skip-hashtab',action='store_true',help='Focused expression iteration only; not acceptance')
    args=parser.parse_args()
    cc=shutil.which(os.environ.get('CC','cc'))
    if not cc: raise SystemExit('SKIP: host C compiler required only for independent ABI oracle')
    hashes=compiler_hashes()
    results=[]
    with tempfile.TemporaryDirectory(prefix='review-floating.') as temporary:
        work=Path(temporary)
        obj=work/'fixture.o'
        run([ROOT/'tests/gcc/sysv-object-compile.sh',ROOT/'tests/gcc/review-floating-fixture.c',obj])
        for opt in ('-O0','-O2'):
            binary=work/('check'+opt[1:])
            run([cc,opt,'-std=c99','-Wall','-Wextra','-Werror','-fno-fast-math',
                 '-fno-pie','-no-pie','-Wl,-z,noexecstack',
                 ROOT/'tests/gcc/review-floating-oracle.c',obj,'-o',binary])
            output=run([binary]).stdout.strip()
            print(output,opt)
            results.append({'kind':'binary64-ABI-oracle','optimization':opt,'output':output})
        object_hash=sha(obj)

        rejects={
            'double-parameter':'double f(double x){return x;}',
            'double-fixed-call':'extern double f(double); double g(void){return f(1);}',
            'double-unprototyped-call':'extern double f(); double g(double *p){return f(*p);}',
            'double-variadic-call':'extern int f(int,...); int g(double *p){return f(1,*p);}',
            'double-indirect-call':'double g(double (*f)(double),double *p){return f(*p);}',
            'float-value':'float f(float *p){return *p;}',
            'long-double-value':'long double f(long double *p){return *p;}',
            'mixed-ternary':'double f(int n,double *p){return n ? *p : 1;}',
            'mixed-ternary-reversed':'double f(int n,double *p){return n ? 1 : *p;}',
            'prefix-increment':'double f(double *p){return ++*p;}',
            'postfix-increment':'double f(double *p){return (*p)++;}',
            'prefix-decrement':'double f(double *p){return --*p;}',
            'postfix-decrement':'double f(double *p){return (*p)--;}',
            'floating-array-index':'double f(double *p,double *i){return p[*i];}',
            'floating-switch':'int f(double *p){switch(*p){case 1:return 1;}return 0;}',
            'static-double-initializer':'double d=1; double f(void){return d;}',
            'double-to-pointer':'void *f(double *p){return (void *)*p;}',
            'pointer-to-double':'double f(void *p){return (double)p;}',
            'double-remainder':'double f(double *p,double *q){return *p % *q;}',
            'double-bitwise':'double f(double *p,double *q){return *p & *q;}',
            'double-shift':'double f(double *p){return *p << 1;}',
            'double-va-arg':'#include <stdarg.h>\ndouble f(int n,...){va_list a;va_start(a,n);return va_arg(a,double);}',
        }
        for name,source in rejects.items():
            path=work/(name+'.c'); path.write_text(source+'\n')
            rejected=work/(name+'.o')
            run([ROOT/'tests/gcc/sysv-object-compile.sh',path,rejected,
                 ROOT/'runtime/gcc-seed/include'],247 if name=='double-va-arg' else 232)
            if rejected.exists(): raise RuntimeError(f'{name}: rejected object was published')
            code=247 if name=='double-va-arg' else 232
            print('PASS:',name,'rejects with',code)
            results.append({'kind':'fail-closed','name':name,'exit':code})

        if not args.skip_hashtab:
            source=args.source_root/'libiberty/hashtab.c'
            header=args.source_root/'include/hashtab.h'
            if not source.is_file() or not header.is_file():
                raise RuntimeError('Original GCC hashtab input missing; use --source-root for its pinned source tree')
            if sha(source)!=HASHTAB_SHA or sha(header)!=HEADER_SHA:
                raise RuntimeError('Original GCC hashtab input hash mismatch')
            htab=work/'hashtab.o'
            run([ROOT/'tools/gcc-direct-cc.py','-c','-DHAVE_STDLIB_H','-DHAVE_STRING_H',
                 '-DHAVE_LIMITS_H','-I'+str(args.source_root/'include'),source,'-o',htab])
            for opt in ('-O0','-O2'):
                binary=work/('htab'+opt[1:])
                run([cc,opt,'-std=c99','-Wall','-Wextra','-Werror','-fno-fast-math',
                     '-fno-pie','-no-pie','-Wl,-z,noexecstack',
                     '-I'+str(args.source_root/'include'),
                     ROOT/'tests/gcc/review-floating-hashtab-oracle.c',htab,'-o',binary])
                output=run([binary]).stdout.strip()
                print(output,opt)
                results.append({'kind':'untouched-hashtab-unit','optimization':opt,'output':output,
                                'source_sha256':HASHTAB_SHA,'header_sha256':HEADER_SHA,
                                'object_sha256':sha(htab)})
    if compiler_hashes()!=hashes:
        raise RuntimeError('Compiler changed during independent review; rerun after source freeze')
    report={'compiler_sha256':hashes,'fixture_object_sha256':object_hash,'results':results,
            'host_tools':'Independent oracles only; no host target code in bootstrap proof',
            'full_hashtab_acceptance':not args.skip_hashtab}
    if args.report: args.report.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print('PASS: floating review compiler inputs remained unchanged')

if __name__=='__main__': main()
