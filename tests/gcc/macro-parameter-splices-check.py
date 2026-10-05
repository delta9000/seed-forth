#!/usr/bin/env python3
"""Bounded SysV parameter-list phase-two proof; host tools are oracles only."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import resource
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]
DRIVER=ROOT/'tools/gcc-direct-cc.py'
spec=importlib.util.spec_from_file_location('tokens',ROOT/'tests/gcc/review-source-location-check.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
def sha(data):return hashlib.sha256(data).hexdigest()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--baseline-root',type=Path);ap.add_argument('--gcc-source',type=Path);a=ap.parse_args()
    resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
    (ROOT/'build-out').mkdir(exist_ok=True)
    work=Path(tempfile.mkdtemp(prefix='parameter-splices-',dir=ROOT/'build-out'))
    report={'memory_limit_bytes':1024**3,'serial':True,'cases':[],'boundaries':[],'source_sha256':{str(p.relative_to(ROOT)):sha(p.read_bytes()) for p in [ROOT/'040-cc-prep.fth',ROOT/'book/22-the-preprocessor.md',DRIVER,Path(__file__)]}}
    def run(argv,status=0,**kwargs):
        p=subprocess.run(list(map(str,argv)),capture_output=True,timeout=180,**kwargs)
        assert p.returncode==status,(argv,p.returncode,p.stdout[-1000:],p.stderr)
        return p
    report['compiler_identity']=run([DRIVER,'--print-source-hash']).stdout.decode().strip()
    def record(name,**more):
        report['cases'].append({'case':name,**more});(work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',name,flush=True)
    def compare(name,data):
        src=work/(name+'.c');src.write_bytes(data)
        actual=run([DRIVER,'-E',src]).stdout;expected=run(['cc','-E','-P',src]).stdout
        (work/(name+'.i')).write_bytes(actual);(work/(name+'.host.i')).write_bytes(expected)
        assert module.tokens(actual)==module.tokens(expected),(name,actual[-500:],expected[-500:])
        record(name,source_sha256=sha(data),actual_sha256=sha(actual),oracle_sha256=sha(expected))
        return src
    def reject(name,data,status=47,host_reject=True):
        src=work/(name+'.c');src.write_bytes(data);out=work/(name+'.i');out.write_bytes(b'previous output\n')
        p=run([DRIVER,'-E',src,'-o',out],status=status)
        assert out.read_bytes()==b'previous output\n' and b'error '+str(status).encode() in p.stderr
        (work/(name+'.stderr')).write_bytes(p.stderr)
        if name=='diagnostic-inside':assert p.stderr.startswith(b'cc: line 3: error 47\n')
        if name=='diagnostic-after':assert p.stderr.startswith(b'cc: line 3: error 40\n')
        hp=subprocess.run(['cc','-E','-P',str(src)],capture_output=True,timeout=90)
        if host_reject:assert hp.returncode!=0,(name,hp.stdout)
        record(name,status=status,diagnostic=p.stderr.decode(),host_status=hp.returncode)
    for ending,nl in [('lf',b'\n'),('crlf',b'\r\n')]:
        join=b'\\'+nl
        cases={
          'empty':b'#define F('+join+b') 41\nF() __LINE__\n',
          'before-first':b'#define F('+join+b'a) a\nF(41) __LINE__\n',
          'before-comma':b'#define F(a'+join+b',b) a+b\nF(1,40) __LINE__\n',
          'after-comma':b'#define F(a,'+join+b'b) a+b\nF(1,40) __LINE__\n',
          'before-close':b'#define F(a'+join+b') a\nF(41) __LINE__\n',
          'after-close':b'#define F(a)'+join+b' a\nF(41) __LINE__\n',
          'before-open':b'#define F'+join+b'(a) a\nF(41) __LINE__\n',
          'split-first':b'#define F(ar'+join+b'g) arg+arg\nF(41) __LINE__\n',
          'split-second':b'#define F(a, ar'+join+b'g) arg+a\nF(1,40) __LINE__\n',
          'repeated':b'#define F('+join*4+b'ar'+join*4+b'g'+join*3+b','+join*3+b' b'+join*2+b') arg+b\nF(1,40) __LINE__\n',
          'whitespace':b'#define F( \t'+join+b' ar'+join+b'g \t'+join+b', \t'+join+b'b \t'+join+b') arg+b\nF(1,40) __LINE__\n',
          'stringify':b'#define F(ar'+join+b'g) #arg\nF(a + b) __LINE__\n',
          'paste':b'#define F(le'+join+b'ft,ri'+join+b'ght) left##right\nF(4,1) __LINE__\n',
          'mapped':b'#line 81 "mapped.y"\n#define F(ar'+join+b'g) arg+__LINE__\nF(__LINE__) __LINE__ __FILE__\n',
          'not-function':b'#define F '+join+b'(a) a\nF __LINE__\n',
        }
        for name,data in cases.items():compare(name+'-'+ending,data)
    for n in [1,16]:
        names=[('p'+str(i)).encode() for i in range(n)]
        compare('limit-'+str(n),b'#define F('+b',\\\n'.join(names)+b') '+b'+'.join(names)+b'\nF('+b','.join([b'1']*n)+b') __LINE__\n')
    compare('logical-storage-exact',b'#define F('+b'a'*32768+b'\\\n'+b'b'*32768+b') 1\nF(0) __LINE__\n')
    reject('logical-storage-over',b'#define F('+b'a'*65536+b'\\\n'+b'b'+b') 1\n',37,False)
    reject('parameter-count-over',b'#define F('+b',\\\n'.join(('p'+str(i)).encode() for i in range(17))+b') 1\n',48,False)
    malformed={
      'leading-comma':b',a','empty-between':b'a,,b','trailing-comma':b'a,','empty-comma':b',',
      'duplicate':b'a,a','joined-duplicate':b'arg,ar\\\ng','duplicate-at-limit':b','.join([('p'+str(i)).encode() for i in range(15)]+[b'p0']),
      'missing-comma':b'a b','punctuation':b'a+b','number':b'1','unterminated':b'a\n','stray-backslash':b'a\\b',
      'space-after-backslash':b'a\\ \nb','bare-newline':b'a,\nb',
    }
    for name,params in malformed.items():reject(name,b'#define F('+params+b') a\nF(1)\n',host_reject=name!='space-after-backslash')
    reject('dangling-join',b'#define F(a\\\n')
    for name,data in {
      'comment':b'#define F(a,/* gap */b) a\n',
      'split-comment':b'#define F(a,/\\\n* gap */b) a\n',
      'variadic':b'#define F(a,...) a\n',
      'gnu-variadic':b'#define F(a,args...) a\n',
      'split-macro-name':b'#define MA\\\nCRO(a) a\n',
    }.items():reject('unsupported-'+name,data,47,False)
    # Split identifiers in replacement bodies and whitespace/comments not in
    # the parameter-list grammar remain preexisting boundaries, not new claims.
    for name,data in {
      'body-split-parameter':b'#define F(arg) ar\\\ng\nF(41)\n',
      'form-feed':b'#define F(a,\fb) a\n',
      'vertical-tab':b'#define F(a,\vb) a\n',
    }.items():
        src=work/(name+'.c');src.write_bytes(data);p=subprocess.run([str(DRIVER),'-E',str(src)],capture_output=True);h=run(['cc','-E','-P',src]);report['boundaries'].append({'case':name,'status':p.returncode,'actual':p.stdout.decode(),'host':h.stdout.decode(),'matches_host':p.returncode==0 and module.tokens(p.stdout)==module.tokens(h.stdout)})
    # A continuation's physical newline remains after a directive; errors in
    # the directive retain the established start-line diagnostics.
    reject('diagnostic-inside',b'\n\n#define F(a,\\\n a) a\n',47)
    reject('diagnostic-after',b'#define F(a,\\\n b) a+b\n#error stopped\n',40)
    include=work/'included.h';include.write_bytes(b'#define INC(pa\\\nram) param+__LINE__\nINC(__LINE__) __LINE__ __FILE__\n')
    compare('physical-include',b'#line 51 "virtual-main.y"\n#include "included.h"\nINC(__LINE__) __LINE__ __FILE__\n')
    # Each definition gives back parameter scratch before scanning the next.
    compare('scratch-reuse',(b'#define F('+b'a'*4096+b'\\\n'+b'b'*4096+b') 1\n#undef F\n')*300+b'__LINE__\n')
    program=compare('execution',b'''#define SUM(le\\
ft,ri\\
ght) ((left)+(right))
#define STR(ar\\
g) #arg
#define CAT(le\\
ft,ri\\
ght) left##right
#define ZERO(\\
) 0
int main(void){
 const char *s = STR(alpha beta);
 if (SUM(19,23)!=42 || CAT(4,2)!=42 || ZERO()!=0) return 1;
 if (s[0]!='a' || s[5]!=' ' || s[9]!='a' || s[10]!=0) return 2;
 return 0;
}
''')
    out=work/'production';run([DRIVER,program,'-o',out]);run([out]);record('forth-execution',sha256=sha(out.read_bytes()))
    for opt in ['-O0','-O2']:
        out=work/('host'+opt);run(['cc',opt,program,'-o',out]);run([out]);record('host-execution'+opt)
    if a.gcc_source:
        src=a.gcc_source/'gcc/c-common.c';data=src.read_bytes();assert sha(data)=='0ac139bcacc0eca1713d610023a1739f589f4699d755d62b24e5d4e5dada092b'
        start=data.index(b'#define DEF_BUILTIN(ENUM, NAME, CLASS, TYPE, LIBTYPE, BOTH_P, FALLBACK_P, \\\n')
        end=data.index(b'#include "builtins.def"',start);definition=data[start:end]
        report['original']={'source':str(src),'sha256':sha(data),'start_line':data[:start].count(b'\n')+1,'definition_sha256':sha(definition)}
        builtins=a.gcc_source/'gcc/builtins.def';report['original']['builtins_sha256']=sha(builtins.read_bytes())
        assert report['original']['builtins_sha256']=='6682c709fef16c3a4672b41ea38e0a97ba63b3a5e8f2f3f3744173613ddaa48f'
        (work/'builtins.def').write_bytes(builtins.read_bytes())
        compare('original-full-def-builtin',definition+b'DEF_BUILTIN(E,"__builtin_x",C,T,L,1,1,0,A,1,1)\n__LINE__\n')
        compare('original-builtins-cohort',definition+b'#include "builtins.def"\n#undef DEF_BUILTIN\n__LINE__\n')
        df=a.gcc_source/'gcc/df.c';data=df.read_bytes();assert sha(data)=='f03e87091956030c1b1b3f9fb49f8a164527f8b994f06b1f765fa02906915111'
        start=data.index(b'#define HS(E_ANTI, E_ANTI_BB, E_ANTI_START_BB, IN_SET,')
        end=data.index(b'\n}',start)
        witness=data[start:end]+b'\n__LINE__\n'
        report['original_df']={'source':str(df),'sha256':sha(data),'start_line':data[:start].count(b'\n')+1,'witness_sha256':sha(witness)}
        compare('original-full-hs',witness)
    else:report['original']='SKIP: supply --gcc-source for pinned original source proof'
    if a.baseline_root:
        baseline=a.baseline_root/'tools/gcc-direct-cc.py';report['baseline_identity']=run([baseline,'--print-source-hash']).stdout.decode().strip()
        changes={
          'after-comma-lf':47,'split-first-lf':47,'leading-comma':0,'trailing-comma':0,'empty-comma':0,'empty-between':0,'duplicate':0,
        }
        for name,status in changes.items():
            src=work/(name+'.c')
            if status==0:
                data=src.read_bytes().removesuffix(b'F(1)\n');src=work/('before-'+name+'.c');src.write_bytes(data)
            p=run([baseline,'-E',src],status=status);record('before-'+name,status=p.returncode,stdout=p.stdout.decode(),stderr=p.stderr.decode())
        # Defaults and native mode retain exact preprocessor/object output.
        for mode in ['legacy','native']:
            text=b'#define F(a,b) ((a)+(b))\n#define Z() 3\nint main(void){return F(19,20)+Z();}\n';src=work/(mode+'.c');src.write_bytes(text)
            outs=[]
            for root,label in [(a.baseline_root,'before'),(ROOT,'after')]:
                out=work/(mode+'-'+label)
                if mode=='native':run(['bash',root/'tests/tcc/compile-native.sh',src,out]);outs.append(out.read_bytes())
                else:
                    mods=[root/'010-lib.fth']+sorted(p for p in root.glob('[0-9][0-9][0-9]-cc-*.fth') if p.name!='120-cc-main.fth')
                    driver=b': proof cc-load-stdin cc-preprocess cc-src-buf cc-src-len @ cc-err-write bye ;\nproof\n'
                    p=run([root/'seed-forth'],input=b'\n'.join(p.read_bytes() for p in mods)+b'\n'+driver+text);outs.append(p.stderr)
            assert outs[0]==outs[1],mode;record(mode+'-byte-preservation',sha256=sha(outs[0]))
    else:report['baseline']='SKIP: supply --baseline-root for exact prior behavior checks'
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('REPORT:',work/'report.json')
if __name__=='__main__':main()
