#!/usr/bin/env python3
"""Independent C90 behavioral/metadata review; Forth builds all target bytes."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TEST = ROOT / 'tests/gcc'
REJECTS = {
    'grouped-return-conflict': 'int (*f(void)); long *f(void);',
    'grouped-record-conflict': 'struct A{int a;};struct B{int b;};struct A (*f(void));struct B *f(void);',
    'grouped-argument-conflict': 'int (*f(unsigned char));int *f(unsigned short);',
    'callback-array-signature-conflict': 'extern int (*a[2])(unsigned char);extern int (*a[2])(unsigned short);',
    'callback-array-return-conflict': 'extern int (*a[2])(int);extern long (*a[2])(int);',
    'callback-array-bound-conflict': 'extern int (*a[2])(int);extern int (*a[3])(int);',
    'callback-too-few': 'struct X{int (*f[2])(int);};int g(struct X *p){return p->f[0]();}',
    'callback-too-many': 'struct X{int (*f[2])(void);};int g(struct X *p){return (*p->f[0])(1);}',
    'callback-record-arg': 'struct R{int x;};struct X{int (*f[2])(struct R);};int g(struct X *p){struct R r;return p->f[0](r);}',
    'callback-record-return': 'struct R{int x;};struct X{struct R (*f[2])(void);};int g(struct X *p){p->f[0]();return 0;}',
    'callback-long-double-arg': 'struct X{int (*f[2])(long double);};int g(struct X *p){return p->f[0](1);}',
    'nested-callback-too-few': 'typedef int (*leaf)(int);struct X{leaf (*f[2])(void);};int g(struct X *p){return p->f[0]()();}',
    'nested-callback-too-many': 'typedef int (*leaf)(void);struct X{leaf (*f[2])(void);};int g(struct X *p){return p->f[0]()(1);}',
    'pointer-to-array': 'int (*a)[3];',
    'array-of-pointer-to-array': 'int (*a[2])[3];',
    'function-return-pointer-to-array': 'int (*f(void))[3];',
    'function-return-function': 'int (f(void))(int);',
    'plain-array-of-functions': 'int f[3](int);',
    'plain-function-field': 'struct X {int f(void);};',
    'grouped-function-field': 'struct X {int (*f(void));};',
    'array-of-functions': 'int (f[2])(int);',
    'array-zero-bound': 'int (*f[0])(int);',
    'array-negative-bound': 'int (*f[-2])(int);',
    'fnptr-extra-depth': 'int (**f[2])(int);',
    'missing-close-group': 'int (*f[2](int);',
    'missing-array-bound-close': 'int (*f[2)(int);',
}

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def run(args, timeout=60):
    return subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)
def checked(args):
    p=run(args)
    assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
    return p

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--work',type=Path)
    args=parser.parse_args()
    work=args.work or Path(tempfile.mkdtemp(prefix='review-declarator-'))
    work.mkdir(parents=True,exist_ok=True)
    inputs=[ROOT/'seed-forth',ROOT/'010-lib.fth',ROOT/'tools/gcc-direct-cc.py',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))]
    inputs += [ROOT/'000-seed.hex0',ROOT/'141-archive.fth',*sorted((ROOT/'runtime/gcc-seed').rglob('*.c')),*sorted((ROOT/'runtime/gcc-seed').rglob('*.h'))]
    hashes={str(p.relative_to(ROOT)):sha(p) for p in inputs}
    cc=ROOT/'tools/gcc-direct-cc.py'
    fixture=TEST/'review-declarator-fixture.c'
    outcomes=[]
    for opt in ('-O0','-O2'):
        exe=work/('host'+opt)
        checked(['gcc','-std=c90','-pedantic-errors',opt,fixture,'-o',exe])
        checked([exe])
        outcomes.append({'mode':'host-source'+opt,'sha256':sha(exe)})
    for mode in ('mapped','linked','object'):
        exe=work/mode
        if mode=='mapped': checked([TEST/'sysv-compile.sh',fixture,exe])
        elif mode=='linked': checked([cc,fixture,'-o',exe])
        else:
            obj=work/'fixture.o'
            checked([cc,'-c',fixture,'-o',obj])
            checked(['gcc','-fno-pie','-no-pie',obj,'-o',exe])
        checked([exe])
        outcomes.append({'mode':mode,'sha256':sha(exe)})
    print('PASS: callback return/narrow/record metadata and empty-loop control flow; five production/oracle executions',flush=True)
    disassembly=checked(['objdump','-dr',work/'fixture.o']).stdout
    calls=disassembly.split('<check_calls>:',1)[1].split('<check_loops>:',1)[0]
    narrow_count=len(re.findall(r'movzbl\s+%dil,%edi',calls))
    assert narrow_count==14,('caller uchar conversion count',narrow_count)
    (work/'caller-conversions.txt').write_text(calls)
    results={}
    for name,source in REJECTS.items():
        src=work/(name+'.c');src.write_text(source+'\n')
        out=work/(name+'.o');out.unlink(missing_ok=True)
        checks=[]
        expected=237 if name.endswith('conflict') else 235 if 'too-few' in name or 'too-many' in name else 232 if name in ('callback-record-arg','callback-record-return','callback-long-double-arg') else 231 if name=='fnptr-extra-depth' else 143 if name.startswith('missing-') else 238
        for mode in ('object','mapped'):
            out.unlink(missing_ok=True)
            for exists in (False,True):
                if exists:out.write_bytes(b'previous valid artifact\x00\xff')
                p=run([cc,'-c',src,'-o',out] if mode=='object' else [TEST/'sysv-compile.sh',src,out])
                preserved=out.read_bytes()==b'previous valid artifact\x00\xff' if exists else not out.exists()
                mode_expected=207 if mode=='mapped' and source.startswith('extern int (*a') else expected
                assert p.returncode==mode_expected and preserved and not p.stdout,(name,mode,p.returncode,p.stdout,p.stderr,preserved)
                checks.append({'mode':mode,'existing_output':exists,'rc':p.returncode,'preserved':preserved,'stderr':p.stderr})
        results[name]=checks
        print(name,checks[0]['rc'],'preserved',all(c['preserved'] for c in checks),flush=True)
    assert hashes=={str(p.relative_to(ROOT)):sha(p) for p in inputs},'compiler changed'
    report={'compiler_source_identity':checked([cc,'--print-source-hash']).stdout.strip(),'compiler_sha256':hashes,'fixture_sha256':sha(fixture),'review_script_sha256':sha(Path(__file__)),'work':str(work),'executions':outcomes,'rejections':results,'caller_unsigned_char_conversions':narrow_count,'caller_disassembly_sha256':sha(work/'caller-conversions.txt')}
    (work/'review-declarator-results.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')
    print(work/'review-declarator-results.json')

if __name__=='__main__':main()
