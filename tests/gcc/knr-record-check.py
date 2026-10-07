#!/usr/bin/env python3
"""Focused C90 identifier-list INTEGER/MEMORY entry and ABI/publication proof."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
CC=ROOT/'tools/gcc-direct-cc.py'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--work',type=Path)
    ap.add_argument('--baseline-root',type=Path)
    args=ap.parse_args()
    work=args.work or Path(tempfile.mkdtemp(prefix='knr-record-',dir=ROOT/'build-out'))
    work.mkdir(parents=True,exist_ok=True)
    rows=[]
    inputs={str(p.relative_to(ROOT)):sha(p) for p in [ROOT/'seed-forth',ROOT/'010-lib.fth',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),CC,Path(__file__)]}
    def run(label,cmd,expected=0,input=None):
        p=subprocess.run(list(map(str,cmd)),cwd=ROOT,capture_output=True,timeout=180,input=input)
        (work/(label+'.stdout')).write_bytes(p.stdout);(work/(label+'.stderr')).write_bytes(p.stderr)
        rows.append({'label':label,'command':list(map(str,cmd)),'expected':expected,'status':p.returncode})
        (work/'steps.json').write_text(json.dumps(rows,indent=2)+'\n')
        assert p.returncode==expected,(label,p.returncode,expected,p.stderr.decode(errors='replace'))
        return p
    types=''.join('struct R%d { unsigned char a[%d]; };\n'%(n,n) for n in range(1,34))
    (work/'types.h').write_text(types)
    api='#include "types.h"\n'
    provider='#include "types.h"\n'
    harness='#include "api.h"\nint main(void) { int i; long got;\n'
    layouts=[]
    for n in range(1,34):
        for g,d in ((0,0),(5,8),(6,9)):
            suffix=f'{n}_{g}_{d}'
            params=[('long',f'g{k}') for k in range(g)]+[('double',f'd{k}') for k in range(d)]+[(f'struct R{n}','v'),('long','tail'),('double','last')]
            decl=', '.join(t+' '+name for t,name in params)
            names=', '.join(name for t,name in params)
            refining=' '.join(t+' '+name+';' for t,name in reversed(params))
            values=[str(13+k) for k in range(g)]+[str(k+2)+'.5' for k in range(d)]+['a','37','19.5']
            checks=' || '.join([f'g{k}!={13+k}' for k in range(g)]+[f'd{k}!={k+2}.5' for k in range(d)]+['tail!=37','last!=19.5'])
            expected=sum((k+3)*(k+1) for k in range(n))
            for ret,name in [('long','take_'+suffix),(f'struct R{n}','give_'+suffix)]:
                prototype=ret+' '+name+'('+decl+');\n'
                api+=prototype
                if n%2==0: provider+=prototype
                provider+=ret+' '+name+'('+names+') '+refining+' { int i; '
                if ret=='long':
                    provider+=f'long sum; if({checks})return -1; sum=0; for(i=0;i<{n};i++)sum+=v.a[i]*(i+1); v.a[0]=231; return sum; }}\n'
                else:
                    provider+=f'if({checks}){{v.a[0]=231;return v;}} for(i=0;i<{n};i++)v.a[i]+=1; return v; }}\n'
            # Every layout is also called through a separately typed callback.
            harness+='{ struct R%d a,b; struct R%d (*cb)(%s); for(i=0;i<%d;i++)a.a[i]=i+3;\n'%(n,n,decl,n)
            harness+='got=take_'+suffix+'('+', '.join(values)+'); if(got!='+str(expected)+')return 1;\n'
            harness+='cb=give_'+suffix+'; b=cb('+', '.join(values)+'); '
            harness+=f'for(i=0;i<{n};i++){{if(a.a[i]!=i+3)return 2;if(b.a[i]!=i+4)return 3;}} }}\n'
            layouts.append({'size':n,'gp_scalars_before':g,'doubles_before':d,'prior_prototype':n%2==0,'parameter_declarations':'reverse identifier-list order'})
    # A realistic pointer+two-unsigned record, scalar default promotions,
    # grouped/reordered declarations, and a callback called by a K&R callee.
    types+='struct Stack { long *p; unsigned used, allocated; };\n'
    (work/'types.h').write_text(types)
    api+='long stack_probe(struct Stack,int,unsigned int,double);\n'
    provider+='long stack_probe(struct Stack,int,unsigned int,double);\nlong stack_probe(s,c,u,d) double d; unsigned short u; signed char c; register struct Stack s; { s.used+=1; return *s.p+s.used+s.allocated+c+u+(long)d; }\n'
    api+='struct R33 call_cb(struct R33 (*)(struct R33,long),struct R33,long);\n'
    provider+='struct R33 call_cb(fn,a,n) long n; struct R33 a; struct R33 (*fn)(struct R33,long); { return fn(a,n); }\n'
    harness='{PRELUDE}'+harness
    callback='struct R33 local_cb(a,n) long n; struct R33 a; { a.a[32]+=n; return a; }\n'
    # A prototype makes the record callback callable while retaining K&R entry.
    callback='struct R33 local_cb(struct R33,long);\n'+callback
    harness=harness.replace('{PRELUDE}','#include "api.h"\n'+callback).replace('#include "api.h"\nint main','int main')
    harness+=' { long q; struct Stack s; q=101; s.p=&q;s.used=3;s.allocated=7;if(stack_probe(s,-4,65530,5.5)!=65643)return 4;if(s.used!=3)return 5; }\n'
    harness+=' { struct R33 a,b; for(i=0;i<33;i++)a.a[i]=i; b=call_cb(local_cb,a,7);if(b.a[32]!=39||a.a[32]!=32)return 6; }\nreturn 0; }\n'
    (work/'api.h').write_text(api);(work/'provider.c').write_text(provider);(work/'harness.c').write_text(harness)
    # unsigned short promotes to int on this target: preserve the correct prior
    # prototype rather than accepting an unsigned-int mismatch.
    for name in ('api.h','provider.c'):
        p=work/name;p.write_text(p.read_text().replace('stack_probe(struct Stack,int,unsigned int,double)','stack_probe(struct Stack,int,int,double)'))
    host=os.environ.get('CC','cc')
    flags=['-std=c90','-pedantic-errors','-fno-pie','-no-pie','-Wl,-z,noexecstack']
    po=work/'provider.o';ho=work/'harness.o'
    run('provider-forth',[CC,'-c',work/'provider.c','-o',po])
    run('harness-forth',[CC,'-c',work/'harness.c','-o',ho])
    run('forth-link',[CC,po,ho,'-o',work/'all-forth']);run('forth-run',[work/'all-forth'])
    for opt in ('-O0','-O2'):
        for name,units in [('host-to-forth',[po,work/'harness.c']),('forth-to-host',[work/'provider.c',ho]),('host-control',[work/'provider.c',work/'harness.c'])]:
            exe=work/(name+opt);run(name+'-build'+opt,[host,*flags,opt,*units,'-o',exe]);run(name+'-run'+opt,[exe])
    # The unchanged definition-free caller guard remains strict. Reject both
    # fresh output and replacement of a previous artifact in every case.
    A='struct A{long x;};';B='struct B{long x;};'
    rejects={
      'empty-result-prior-count':(237,A+'struct A f(int);struct A f(){struct A a;return a;}'),
      'float-entry':(232,A+'long f(a,x) struct A a;float x;{return a.x;}'),
      'float-entry-prior-double':(232,A+'long f(struct A,double);long f(a,x) float x;struct A a;{return a.x;}'),
      'scalar-float-entry':(232,'long f(x)float x;{return 0;}'),
      'floating-record':(232,'struct A{double x;};long f(a)struct A a;{return 0;}'),
      # Records containing binary64 members still lack an ABI classifier.
      'long-double-record':(232,'struct A{long double x;double d;};long f(a)struct A a;{return 0;}'),
      'prior-record-identity':(237,A+B+'long f(struct B);long f(a)struct A a;{return a.x;}'),
      'prior-return-identity':(237,A+B+'struct B f(struct A);struct A f(a)struct A a;{return a;}'),
      'prior-count':(237,A+'long f(struct A,long);long f(a)struct A a;{return a.x;}'),
      'prior-promoted-type':(237,A+'long f(struct A,unsigned int);long f(a,x)struct A a;unsigned short x;{return a.x;}'),
      'wrong-call-identity':(232,A+B+'long f(struct A);long f(a)struct A a;{return a.x;}long g(void){struct B b;return f(b);}'),
      'wrong-return-identity':(232,A+B+'struct A f(a)struct B a;{return a;}'),
      'wrong-callback-identity':(237,A+B+'long f(a)struct A a;{return a.x;}void g(void){long(*p)(struct B);p=f;}'),
      'undeclared-name':(233,A+'long f(a)struct A b;{return 0;}'),
      'duplicate-declaration':(233,A+'long f(a)struct A a;struct A a;{return 0;}'),
      'sizeof-wrong-call':(232,A+B+'long f(struct A);long f(a)struct A a;{return a.x;}long g(void){struct B b;return sizeof(f(b));}'),
    }
    # Records cross unprototyped and variadic boundaries unchanged by default
    # promotions (record-varargs-check.py runs them against host GCC).
    accepts={
      "long-double-entry":A+"long f(a,x)struct A a;long double x;{return x;}",
      'no-prototype-after-definition':A+'long f(a) struct A a;{return a.x;}long g(void){struct A a;return f(a);}',
      'no-prototype-result':A+'struct A f(a) struct A a;{return a;}void g(void){struct A a;a=f(a);}',
      'unprototyped-pointer':A+'long f(a) struct A a;{return a.x;}long g(void){long(*p)();struct A a;p=f;return p(a);}',
      'unprototyped-external':A+'long f();long g(void){struct A a;return f(a);}',
      'empty-result':A+'struct A f(){struct A a;return a;}',
      'empty-result-prior-void':A+'struct A f(void);struct A f(){struct A a;return a;}',
      'variadic-record':A+'long f(struct A a,...){return a.x;}',
      'variadic-result':A+'struct A f(int x,...){struct A a;return a;}',
      'variadic-call':A+'long f(int,...);long g(void){struct A a;return f(1,a);}',
    }
    for name,src in accepts.items():
        source=work/(name+'.c');source.write_text(src+'\n')
        run(name+'-accepted',[CC,'-c',source,'-o',work/(name+'.o')])
    for name,(expected,src) in rejects.items():
        source=work/(name+'.c');source.write_text(src+'\n');out=work/(name+'.o')
        for prior in (False,True):
            out.unlink(missing_ok=True)
            if prior:out.write_bytes(b'previous valid artifact\x00\xff')
            run(name+('-prior' if prior else '-absent'),[CC,'-c',source,'-o',out],expected)
            assert out.read_bytes()==b'previous valid artifact\x00\xff' if prior else not out.exists()
    # Named K&R scalar/native code generation must be exactly unchanged.
    comparisons=[]
    if args.baseline_root:
        base=args.baseline_root.resolve()
        for name in ('sysv-knr.c','sysv-interop.c','aggregate-production.c','binary64-arguments-provider.c'):
            source=ROOT/'tests/gcc'/name
            assert source.exists(),source
            a=work/(name+'.base.o');b=work/(name+'.new.o')
            run(name+'-base',[base/'tools/gcc-direct-cc.py','-c',source,'-o',a]);run(name+'-new',[CC,'-c',source,'-o',b])
            assert a.read_bytes()==b.read_bytes(),name
            comparisons.append({'path':'tests/gcc/'+name,'sha256':sha(a),'kind':'object'})
        for name in ('basics','layout','stack-call','literals','many-args','initializers'):
            source=ROOT/'tests/tcc'/('native-'+name+'.c')
            assert source.exists(),source
            a=work/('native-'+name+'.base');b=work/('native-'+name+'.new')
            run('native-'+name+'-base',[base/'tests/tcc/compile-native.sh',source,a]);run('native-'+name+'-new',[ROOT/'tests/tcc/compile-native.sh',source,b])
            assert a.read_bytes()==b.read_bytes(),name
            run('native-'+name+'-run',[b]);comparisons.append({'path':str(source.relative_to(ROOT)),'sha256':sha(a),'kind':'native ELF'})
        # The default compiler driver uses the same loaded libraries but keeps
        # System V disabled. Its fixed output pathname is isolated by the
        # external bounded supervisor's private /tmp mount.
        for label,source in [('scalar','int add(int a,int b){return a+b;} int main(){return add(2,3)-5;}'),('loop','int main(){int i;int s;s=0;for(i=0;i<10;i=i+1)s=s+i;return s-45;}')]:
            objects=[]
            for root,epoch in ((base,'base'),(ROOT,'new')):
                layers=[root/'010-lib.fth',*[p for p in sorted(root.glob('[0-9][0-9][0-9]-cc-*.fth')) if p.name!='120-cc-main.fth'],root/'120-cc-main.fth']
                out=Path('/tmp/cc-out');out.unlink(missing_ok=True)
                run('default-'+label+'-'+epoch,[root/'seed-forth'],input=b'\n'.join(p.read_bytes() for p in layers)+b'\n'+source.encode()+b'\n')
                target=work/('default-'+label+'.'+epoch);shutil.copy2(out,target);target.chmod(0o755);objects.append(target)
            assert objects[0].read_bytes()==objects[1].read_bytes(),label
            run('default-'+label+'-run',[objects[1]])
            comparisons.append({'fixture':'default-'+label,'sha256':sha(objects[0]),'kind':'default ELF'})
    assert inputs=={n:sha(ROOT/n) for n in inputs},'inputs changed during proof'
    report={'compiler_test_inputs':inputs,'layouts':layouts,'record_sizes':list(range(1,34)),'directions':['Forth only','host O0/O2 callers','host O0/O2 K&R callees','host O0/O2 all-host controls'],'functions':2*len(layouts)+2,'rejections':list(rejects),'byte_comparisons':comparisons,'steps':rows,'accepted':list(accepts),'claim':'Focused record definition-entry extension; unprototyped and variadic record calls are compiled here and executed in record-varargs-check.py; no full GCC build'}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: K&R record entry sizes1–33, 99 layouts, INTEGER/MEMORY returns, callbacks, ordered refinement and host O0/O2')
    print('PASS:',len(rejects),'rejection/publication cases;',len(comparisons),'unchanged objects/native ELFs')
    print(work/'report.json')
if __name__=='__main__':main()
