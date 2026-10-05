#!/usr/bin/env python3
"""Scoped qualification provenance guards; no host target compiler."""
from pathlib import Path
import json, os, subprocess, sys
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build-out/qualifier-check';OUT.mkdir(parents=True,exist_ok=True)
REJECT={}
for q in ['const','volatile','restrict']:
 for label,src in {
  'prefix':f'{q} long (*p)[2];',
  'pointer':f'long (*{q} p)[2];',
  'typedef':f'typedef long A[2]; {q} A *p;',
  'scalar-alias':f'typedef {q} long Q; typedef Q A[2]; typedef A B; B *p;',
  'array-alias':f'typedef {q} long A[2]; typedef A B; B *p;',
  'descriptor-type-name':f'typedef long (*P)[2];long f(void){{return sizeof({q} P);}}',
  'descriptor-alias':f'typedef long (*P)[2]; {q} P p;',
  'parameter':f'void f({q} long (*p)[2]);',
  'abstract':f'long f(void){{return sizeof({q} long (*)[2]);}}',
  'abstract-pointer':f'long f(void){{return sizeof(long (*{q})[2]);}}',
  'cast':f'long f(void){{return sizeof(({q} long (*)[2])0);}}',
  'global-address':f'{q} long a[2];long f(void){{return sizeof(&a);}}',
  'local-address':f'long f(void){{{q} long a[2];return sizeof(&a);}}',
  'field-address':f'struct S{{{q} long a[2];}};long f(struct S *s){{return sizeof(&s->a);}}',
  'qualified-record':f'struct S{{long a[2];}};long f({q} struct S *s){{return sizeof(&s->a);}}',
  'record-arithmetic':f'struct S{{long a[2];}};long f({q} struct S *s){{return sizeof(&(s+1)->a);}}',
  'record-conditional':f'struct S{{long a[2];}};long f({q} struct S *s,struct S*t,int n){{return sizeof(&(n?s:t)->a);}}',
  'return-qualified':f'struct S{{long a[2];}};{q} struct S *get(void);long f(void){{return sizeof(&get()->a);}}',
  'indirect-return-qualified':f'struct S{{long a[2];}};{q} struct S *(*get)(void);long f(void){{return sizeof(&(*get)()->a);}}',
  'assignment-expression':f'struct S{{long a[2];}};long f({q} struct S *s){{{q} struct S *p;return sizeof(&(p=s)->a);}}',
  'postfix-expression':f'struct S{{long a[2];}};long f({q} struct S *p){{return sizeof(&(p++)->a);}}',
  'prefix-expression':f'struct S{{long a[2];}};long f({q} struct S *p){{return sizeof(&(++p)->a);}}',
  'nested-signature':f'void f(void (*g)({q} long (*)[2]));',
  'two-dimensional-parameter':f'void f({q} long a[2][3]);',
 }.items():REJECT[q+'-'+label]=src
REJECT.update({
 'constant-record-cast':'struct S{long a[2];};long (*p)[2]=&(*(const struct S*)0).a;',
 'constant-nested-cast':'struct S{long a[2];};long (*p)[2]=&(*(1?(const struct S*)0:(struct S*)0)).a;',
 'multidimensional-decay':'long f(void){const long a[2][3]={{1,2,3},{4,5,6}};long (*p)[3]=a;return (*p)[0];}',
})
CONTROLS={
 'constant-record-control':'struct S{long a[2];};long (*p)[2]=&(*(struct S*)0).a;int main(void){return (long)p!=0;}',

 'plain':'typedef long A[2]; long main(void){A a; A *p; p=&a; (*p)[1]=19; return a[1]!=19 || sizeof(*p)!=16;}',
 'ordinary-qualified':'const long n=2; volatile long a[2]; long main(void){a[1]=n; return a[1]!=2;}',
 'ordinary-pointer':'long main(void){long n; long *const p=&n; *p=7;return n!=7;}',
 'comma-reset':'long *const q, (*p)[2]; long main(void){return sizeof(*p)!=16;}',
 'signature-reset':'void f(const long *p, long (*a)[2]); long main(void){return 0;}',
 'nested-signature-reset':'void f(void (*g)(const long *),long (*a)[2]);long main(void){return 0;}',
 'scope-reuse':'long main(void){{const long a[2];}{long a[2];long (*p)[2];p=&a;(*p)[1]=8;if(a[1]!=8)return 1;}return 0;}',
 'sizeof-reset':'long main(void){long a[2];long (*p)[sizeof(const long)/4];p=&a;(*p)[1]=9;return a[1]!=9;}',
 'ordinary-call':'long get(void){return 7;}long main(void){return get()!=7;}',
 'ordinary-indirect-call':'long get(void){return 7;}long main(void){long (*p)(void)=get;return (*p)()!=7;}',
 'ordinary-assignment':'long main(void){long a,b;a=(b=7);return a!=7||b!=7;}',
 'ordinary-increment':'long main(void){long a=2,b;b=a++;return a!=3||b!=2||++a!=4;}',
 'ordinary-cast':'long main(void){long n;n=(long)9;return n!=9;}',
 'ordinary-member':'struct S{const long a[2];};long main(void){struct S s;return sizeof(s.a)!=16;}',
}
results=[]
env=os.environ.copy();env['LC_ALL']='C';env['PYTHONWARNINGS']="ignore:'maxsplit' is passed as positional argument:DeprecationWarning"
def run(args):return subprocess.run(list(map(str,args)),capture_output=True,env=env,timeout=120)
for name,src in REJECT.items():
 c=OUT/(name+'.c');o=OUT/(name+'.o');c.write_text(src);o.write_bytes(b'preserve-existing-output\n')
 p=run([sys.executable,ROOT/'tools/gcc-direct-cc.py','-c',c,'-o',o]);ok=p.returncode==238 and o.read_bytes()==b'preserve-existing-output\n'
 results.append({'name':name,'expected':238,'actual':p.returncode,'pass':ok,'stderr':p.stderr.decode()})
for name,src in CONTROLS.items():
 c=OUT/(name+'.c');exe=OUT/(name+'.elf');c.write_text(src)
 p=run([ROOT/'tests/gcc/sysv-compile.sh',c,exe]);q=run([exe]) if p.returncode==0 else None
 results.append({'name':name,'expected':0,'actual':p.returncode,'execution':q.returncode if q else None,'pass':p.returncode==0 and q.returncode==0,'stderr':p.stderr.decode()})
(OUT/'report.json').write_text(json.dumps(results,indent=2)+'\n')
failed=[x for x in results if not x['pass']]
print(json.dumps({'passed':len(results)-len(failed),'total':len(results),'failures':failed},indent=2));sys.exit(bool(failed))
