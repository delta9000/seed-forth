#!/usr/bin/env python3
"""Forth-produced INTEGER/MEMORY record ABI and independent host ABI oracles."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
TEST=ROOT/'tests/gcc'
REJECTS={
 'float-member':'struct A{float a;}; int f(struct A a){return 0;}',
 'double-member':'struct A{double a;}; struct A f(void){struct A a;return a;}',
 'large-floating-member':'struct A{long a[3];double b;};int f(struct A a){return 0;}',
 'nested-floating':'struct A{double x;};struct B{struct A a[2];};void f(struct B b){}',
 'union-floating':'union A{long a;double b;};void f(union A a){}',
 'long-double':'struct A{long double a;float f;};void f(struct A a){}',
 'variadic-fixed':'struct A{int a;};void f(struct A a,...){}',
 'variadic-result':'struct A{int a;};struct A f(int n,...){struct A a;return a;}',
 'variadic-value':'struct A{int a;};void f(int,...);void g(void){struct A a;f(1,a);}',
 'unprototyped':'struct A{int a;};struct A f();void g(void){f();}',
 'knr-record-unprototyped-call':'struct A{int a;};int f(a) struct A a; {return a.a;} int g(void){struct A a;return f(a);}',
 'wrong-argument':'struct A{int a;};struct B{int a;};int f(struct A);int g(void){struct B b;return f(b);}',
 'scalar-argument':'struct A{int a;};int f(struct A);int g(void){return f(3);}',
 'wrong-return':'struct A{int a;};struct B{int a;};struct A f(void){struct B b;return b;}',
 'wrong-assignment':'struct A{int a;};struct B{int a;};void f(void){struct A a;struct B b;a=b;}',
 'scalar-assignment':'struct A{int a;};void f(void){struct A a;a=3;}',
 'record-add':'struct A{int a;};void f(void){struct A a,b;a=a+b;}',
 'record-compare':'struct A{int a;};int f(void){struct A a,b;return a==b;}',
 'record-condition':'struct A{int a;};int f(void){struct A a;if(a)return 1;return 0;}',
 'record-not':'struct A{int a;};int f(void){struct A a;return !a;}',
 'record-negate':'struct A{int a;};void f(void){struct A a;a=-a;}',
 'record-index':'struct A{int a;};int f(int *p){struct A a;return p[a];}',
 'record-conditional':'struct A{int a;};struct B{int a;};void f(int n){struct A a;struct B b;a=n?a:b;}',
 'empty':'struct A{};void f(struct A a){}',
 'sizeof-wrong-argument':'struct A{long x;};struct B{long x;};struct A f(struct A);long g(void){struct B b;return sizeof(f(b));}',
 'sizeof-wrong-indirect-argument':'struct A{long x;};struct B{long x;};struct A (*f)(struct A);long g(void){struct B b;return sizeof(f(b));}',
 'sizeof-scalar-argument':'struct A{long x;};struct A f(struct A);long g(void){return sizeof(f(7));}',
 'same-record-cast':'struct A{long x;};long g(void){struct A a;(struct A)a;return 0;}',
 'different-record-cast':'struct A{long x,y,z;};struct B{long x;};struct A f(struct B b){return (struct A)b;}',
 'sizeof-record-cast':'struct A{long x;};long g(void){struct A a;return sizeof((struct A)a);}',
 'static-record-cast':'struct A{long x;};long g=(struct A)0;',
 'static-skipped-record-cast':'struct A{long x;};long g=0&&(struct A)0;',
 'scalar-record-init':'struct A{long x;};long f(struct A a){long b=a;return b;}',
 'pointer-record-init':'struct A{long x;};long *f(struct A a){long *b=a;return b;}',
 'array-record-init':'struct A{long x;};long f(struct A a){long b[1]={a};return b[0];}',
 'field-record-init':'struct A{long x;};struct B{long x;};long f(struct A a){struct B b={a};return b.x;}',
 'bitfield-record-init':'struct A{long x;};struct B{unsigned x:3;};int f(struct A a){struct B b={a};return b.x;}',
 'record-call-scalar-init':'struct A{long x;};struct A h(void);long f(void){long b=h();return b;}',
 'sizeof-unary-plus-record':'struct A{long x;};long f(struct A a){return sizeof(+a);}',
 'void-return-record':'struct A{long x;};void f(struct A a){return a;}',

}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(command,expected=0,input=None):
 p=subprocess.run([str(x) for x in command],input=input,capture_output=True,timeout=120)
 assert p.returncode==expected,(command,p.returncode,p.stdout,p.stderr)
 return p

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--oracle',action='store_true');ap.add_argument('--work',type=Path)
 ap.add_argument('--source-root',type=Path);args=ap.parse_args()
 if args.source_root is None:
  default_source=ROOT/'build-out/direct-gcc-inputs/gcc-source'
  if (default_source/'gcc/real.c').is_file():args.source_root=default_source
 work=args.work or Path(tempfile.mkdtemp(prefix='aggregate-abi-',dir=ROOT/'build-out'));work.mkdir(parents=True,exist_ok=True)
 cc=ROOT/'tools/gcc-direct-cc.py';inputs=[ROOT/'seed-forth',ROOT/'010-lib.fth',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),cc,*sorted(TEST.glob('aggregate-*'))]
 inputs=[p for p in inputs if p.is_file()]; hashes={str(p.relative_to(ROOT)):sha(p) for p in inputs}
 report={'production_host_target_tools':False,'compiler_and_test_sha256':hashes,'executions':[],'rejections':{}}
 obj=work/'aggregate.o';run([cc,'-c',TEST/'aggregate-production.c','-o',obj])
 production=work/'production';run([cc,obj,TEST/'aggregate-host.c','-o',production]);run([production])
 report['executions'].append({'name':'Forth-only separate units','sha256':sha(production)})
 mapped=work/'mapped';source=work/'mapped.c';source.write_text('#include "aggregate-production.c"\n#include "aggregate-host.c"\n')
 run([TEST/'sysv-compile.sh',source,mapped,TEST]);run([mapped]);report['executions'].append({'name':'Forth mapped ELF','sha256':sha(mapped)})
 print('PASS: Forth-only record arguments, results, nested lifetimes, independent copies and register rollback',flush=True)
 for name,source in REJECTS.items():
  path=work/(name+'.c');path.write_text(source+'\n');records=[]
  for existing in (False,True):
   out=work/(name+'.o');out.unlink(missing_ok=True)
   if existing:out.write_bytes(b'previous-valid-object\x00\xff')
   expected=240 if name.startswith('static-') else 232
   result=run([cc,'-c',path,'-o',out],expected)
   assert ('error '+str(expected)).encode() in result.stderr
   assert out.read_bytes()==b'previous-valid-object\x00\xff' if existing else not out.exists()
   records.append({'existing_output':existing,'status':result.returncode})
  report['rejections'][name]=records
 print(f'PASS: {len(REJECTS)} unsupported/invalid forms preserve output publication',flush=True)
 metadata=work/'sizeof-metadata.c';metadata.write_text('struct A{double x;long y;};struct A f(struct A);struct A (*p)(struct A);int main(void){struct A a;return sizeof(f(a))!=16||sizeof(p(a))!=16||sizeof(a=a)!=16;}\n')
 metadata_exe=work/'sizeof-metadata';run([cc,metadata,'-o',metadata_exe]);run([metadata_exe])
 report['executions'].append({'name':'unsupported ABI metadata-only sizeof','sha256':sha(metadata_exe)})
 constraints=work/'constraints';run([cc,TEST/'aggregate-constraints.c','-o',constraints]);run([constraints])
 report['executions'].append({'name':'valid scalar/record initialization, unary promotion, sizeof metadata and void discards','sha256':sha(constraints)})
 # A synthetic descriptor tests classification of layouts the parser cannot
 # yet express (packed/unaligned); it is never substituted for a C ABI proof.
 layers=[ROOT/'010-lib.fth',*[p for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')) if p.name!='120-cc-main.fth']]
 script='''cc-sysv-enable
[lit] 8388608 cc-arena-map
cc-sd-alloc constant probe
[lit] 5 probe cc-sd-set-total-size
[lit] 1 probe cc-sd-set-align
[lit] 1 probe cc-sd-set-field-count
probe [lit] 0 cc-sd-field-rec constant member
ty-int [lit] 0 ty-make member cc-sf-set-type
[lit] 1 member cc-sf-set-offset
ty-struct [lit] 0 ty-make probe cc-ag-class [lit] 0 <> if [lit] 1 exit then
[lit] 4 probe cc-sd-set-total-size
[lit] 4 probe cc-sd-set-align
[lit] 0 member cc-sf-set-offset
ty-struct [lit] 0 ty-make probe cc-ag-class [lit] 1 <> if [lit] 2 exit then
bye
'''
 # Interpretive IF is unavailable: use one compiled test word around checks.
 script=script.replace('ty-struct [lit] 0 ty-make probe cc-ag-class [lit] 0 <> if [lit] 1 exit then',': check-memory ty-struct [lit] 0 ty-make probe cc-ag-class if, [lit] 232 cc-die then, ; check-memory').replace('ty-struct [lit] 0 ty-make probe cc-ag-class [lit] 1 <> if [lit] 2 exit then',': check-integer ty-struct [lit] 0 ty-make probe cc-ag-class [lit] 1 <> if, [lit] 232 cc-die then, ; check-integer')
 result=run([ROOT/'seed-forth'],input=b'\n'.join(p.read_bytes() for p in layers)+b'\n'+script.encode());assert not result.stdout and not result.stderr
 report['classifier']='synthetic unaligned field MEMORY, aligned field INTEGER'
 if args.source_root:
  real=args.source_root/'gcc/real.c';header=args.source_root/'gcc/real.h'
  expected={'gcc/real.c':'', 'gcc/real.h':''}
  # Pins filled from the independently pinned original source archive.
  pins=json.loads((TEST/'aggregate-source-pins.json').read_text())
  for name,value in pins.items():assert sha(args.source_root/name)==value, 'original source changed: '+name
  text=real.read_text();h=header.read_text();descriptor=h[h.index('struct real_value GTY(())'):h.index('\n#define REAL_EXP')]
  prelude='#define GTY(x)\n#define HOST_BITS_PER_LONG 64\n#define EXP_BITS (32-5)\n#define SIGSZ 3\n'+descriptor+'\n#define REAL_VALUE_TYPE struct real_value\nenum machine_mode { MODE_TEST=7 };\n'
  prelude+='void real_convert(REAL_VALUE_TYPE *,enum machine_mode,const REAL_VALUE_TYPE *);\nvoid real_arithmetic(REAL_VALUE_TYPE *,int,const REAL_VALUE_TYPE *,const REAL_VALUE_TYPE *);\n'
  functions=[]
  for name in ('real_value_truncate','real_arithmetic2'):
   start=text.index('REAL_VALUE_TYPE\n'+name+' (');end=text.index('\n}',start)+2;functions.append(text[start:end])
  selected=work/'original-real-functions.c';selected.write_text(prelude+'\n'.join(functions)+'\n')
  harness=work/'real-harness.c';harness.write_text(prelude+'''
REAL_VALUE_TYPE real_value_truncate(enum machine_mode,REAL_VALUE_TYPE);
REAL_VALUE_TYPE real_arithmetic2(int,const REAL_VALUE_TYPE *,const REAL_VALUE_TYPE *);
void real_convert(REAL_VALUE_TYPE *r,enum machine_mode mode,const REAL_VALUE_TYPE *a){*r=*a;r->sig[2]+=mode;r->sign=!a->sign;}
void real_arithmetic(REAL_VALUE_TYPE *r,int code,const REAL_VALUE_TYPE *a,const REAL_VALUE_TYPE *b){*r=*a;r->sig[0]+=b->sig[0]+code;r->uexp+=b->uexp;}
int main(void){REAL_VALUE_TYPE a={1,1,0,1,35,{101,203,307}};REAL_VALUE_TYPE b={2,0,1,0,19,{11,13,17}};REAL_VALUE_TYPE r;
r=real_value_truncate(MODE_TEST,a);if(r.sign!=0||r.cl!=1||r.uexp!=35||r.sig[2]!=314||a.sig[2]!=307)return 1;
r=real_arithmetic2(5,&a,&b);if(r.sig[0]!=117||r.uexp!=54||r.sig[1]!=203||a.sig[0]!=101)return 2;return 0;}
''')
  original_obj=work/'original-real.o';run([cc,'-c',selected,'-o',original_obj]);exe=work/'original-real';run([cc,original_obj,harness,'-o',exe]);run([exe])
  report['original_source']={'pins':pins,'selection_sha256':sha(selected),'object_sha256':sha(original_obj),'functions':['real_value_truncate','real_arithmetic2'],'scope':'Exact function bodies and descriptor; test shims for real_convert/real_arithmetic, not the complete real.c unit'}
  print('PASS: exact original REAL_VALUE_TYPE descriptor and two original record-return wrappers with explicit test shims',flush=True)
 if args.oracle:
  host=shutil.which('cc');assert host
  providers=work/'host-providers.c';providers.write_text((TEST/'aggregate-host.c').read_text().split('int main(void)')[0])
  oracle_inputs=[('interop',[TEST/'aggregate-host.c',obj]),('guard',[TEST/'aggregate-guard.c',providers,obj]),('constraints',[TEST/'aggregate-constraints.c'])]
  if args.source_root:oracle_inputs.append(('original-real',[harness,original_obj]))
  else:print('SKIP: exact original GCC record wrappers require the separately pinned source archive',flush=True)
  for opt in ('-O0','-O2'):
   for name,files in oracle_inputs:
    exe=work/(name+opt);run([host,opt,'-I'+str(TEST),'-fno-pie','-no-pie','-Wl,-z,noexecstack',*files,'-o',exe]);run([exe]);report['executions'].append({'name':name+opt,'sha256':sha(exe)})
  print('PASS: independent O0/O2 cross-ABI, protected-page tails and valid-constraint oracles',flush=True)
 assert hashes=={str(p.relative_to(ROOT)):sha(p) for p in inputs},'compiler or tests changed during proof'
 (work/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(work/'report.json')
if __name__=='__main__':main()
