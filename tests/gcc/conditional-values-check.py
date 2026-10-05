#!/usr/bin/env python3
"""Selected-arm C conditional typing, host oracles, and bounded null provenance.

Use unique --work paths. This focused runner is serial and caps each child's
address space at 1GiB; its supervising caller owns the whole-group timeout.
No source adaptation, host-preprocessed input or production host object is used.
"""
from pathlib import Path
import argparse,hashlib,json,resource,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
TEST=ROOT/'tests/gcc'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--work',type=Path);a=ap.parse_args()
 w=(a.work or Path(tempfile.mkdtemp(prefix='conditional-'))).resolve();w.mkdir(parents=True,exist_ok=True)
 resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
 paths=[ROOT/'seed-forth',ROOT/'010-lib.fth',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),ROOT/'tools/gcc-direct-cc.py',*sorted(TEST.glob('conditional-values*'))]
 hashes={str(p.relative_to(ROOT)):sha(p) for p in paths if p.is_file()}
 report={'compiler_and_test_sha256':hashes,'runs':[],'negative_cases':{}}
 def run(cmd,expected=0):
  p=subprocess.run([str(c) for c in cmd],capture_output=True,text=True,timeout=180)
  report['runs'].append({'command':[str(c) for c in cmd],'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
  (w/'report.json').write_text(json.dumps(report,indent=2)+'\n')
  if p.returncode!=expected:raise RuntimeError(f'{cmd}: expected {expected}, got {p.returncode}\n{p.stdout}{p.stderr}')
  return p
 direct=[ROOT/'tools/gcc-direct-cc.py'];provider=TEST/'conditional-values.c';main=TEST/'conditional-values-main.c'
 for opt in ('-O0','-O2'):
  exe=w/('host'+opt);run(['gcc','-std=c90','-pedantic-errors',opt,'-fno-fast-math','-ffp-contract=off',provider,main,'-o',exe]);run([exe],42)
  print('PASS: host C90 oracle',opt,flush=True)
 sfobj=w/'sf-provider.o';sfmain=w/'sf-main.o'
 run([*direct,'-c',provider,'-o',sfobj]);run([*direct,'-c',main,'-o',sfmain])
 for opt in ('-O0','-O2'):
  exe=w/('sf-provider-host-caller'+opt);run(['gcc','-std=c90','-pedantic-errors',opt,'-no-pie',sfobj,main,'-o',exe]);run([exe],42)
  exe=w/('host-provider-sf-caller'+opt);run(['gcc','-std=c90','-pedantic-errors',opt,'-no-pie',provider,sfmain,'-o',exe]);run([exe],42)
  print('PASS: bidirectional mixed ABI',opt,flush=True)
 exe=w/'forth-only';run([*direct,sfobj,sfmain,'-o',exe]);run([exe],42)
 print('PASS: Forth-only objects and linker',flush=True)
 prefix='struct S{int value;}; '
 # host_valid distinguishes documented conservative boundaries from invalid C.
 cases={
  'nonzero-integer-left':('int *f(int c,int *p){return c?1:p;}',237,False),
  'nonzero-integer-right':('int *f(int c,int *p){return c?p:1;}',237,False),
  'runtime-integer-left':('int *f(int c,int z,int *p){return c?z:p;}',237,False),
  'runtime-integer-right':('int *f(int c,int z,int *p){return c?p:z;}',237,False),
  'comma-zero-left':('int *f(int c,int *p){return c?(1,0):p;}',237,False),
  'comma-zero-right':('int *f(int c,int *p){return c?p:(1,0);}',237,False),
  'comma-void-zero-left':(prefix+'int f(int c,struct S *p){return (c?(void*)(1,0):p)->value;}',238,False),
  'comma-void-zero-right':(prefix+'int f(int c,struct S *p){return (c?p:(void*)(1,0))->value;}',238,False),
  'runtime-void-left':(prefix+'int f(int c,void *v,struct S *p){return (c?v:p)->value;}',238,False),
  'runtime-void-right':(prefix+'int f(int c,void *v,struct S *p){return (c?p:v)->value;}',238,False),
  'cast-runtime-zero-left':(prefix+'int f(int c,int z,struct S *p){return (c?(void*)z:p)->value;}',238,False),
  'cast-runtime-zero-right':(prefix+'int f(int c,int z,struct S *p){return (c?p:(void*)z)->value;}',238,False),
  'pointer-cast-zero-left':(prefix+'int f(int c,struct S *p){return (c?(void*)(int*)0:p)->value;}',238,False),
  'pointer-integer-zero-roundtrip':(prefix+'int f(int c,struct S *p){return (c?p:(void*)(long)(void*)0)->value;}',238,False),
  'assignment-zero-left':('int *f(int c,int z,int *p){return c?(z=0):p;}',237,False),
  'incompatible-record-pointers':('struct A{int x;};struct B{int x;};void *f(int c,struct A *a,struct B *b){return c?a:b;}',237,False),
  'incompatible-element-pointers':('void *f(int c,int *a,char *b){return c?a:b;}',237,False),
  'pointer-floating-left':('void *f(int c,double d,void *p){return c?d:p;}',232,False),
  'pointer-floating-right':('void *f(int c,double d,void *p){return c?p:d;}',232,False),
  'function-runtime-void':('void *f(int c,void *v,int (*p)(int)){return c?v:p;}',237,False),
  'incompatible-function-pointers':('void f(int c,int (*p)(int),int (*q)(double)){c?p:q;}',237,False),
  'incompatible-record-values':('struct A{int x;};struct B{int x;};void f(int c,struct A a,struct B b){c?a:b;}',232,False),
  'void-integer-mixed':('int f(int c){return c?(void)0:1;}',237,False),
  'general-zero-ice-left':('int *f(int c,int *p){return c?(1-1):p;}',237,True),
  'general-zero-ice-right':('int *f(int c,int *p){return c?p:(2-2);}',237,True),
  'general-zero-ice-void':(prefix+'int f(int c,struct S *p){return (c?(void*)(1-1):p)->value;}',238,True),
 }
 for name,(body,expected,host_valid) in cases.items():
  src=w/(name+'.c');src.write_text(body+'\n');obj=w/(name+'.o')
  host=subprocess.run(['gcc','-std=c90','-pedantic-errors','-fsyntax-only',str(src)],capture_output=True,text=True,timeout=30)
  if (host.returncode==0)!=host_valid:raise RuntimeError(f'host validity disagreement {name}: {host.stderr}')
  for existing in (False,True):
   obj.unlink(missing_ok=True)
   if existing:obj.write_bytes(b'previous object\x00\xff')
   run([*direct,'-c',src,'-o',obj],expected)
   assert obj.read_bytes()==b'previous object\x00\xff' if existing else not obj.exists()
  report['negative_cases'][name]={'expected_status':expected,'host_valid_c90':host_valid,'host_stderr':host.stderr,'absent_and_existing_output_preserved':True}
  print('PASS:',name,flush=True)
 assert hashes=={str(p.relative_to(ROOT)):sha(p) for p in paths if p.is_file()},'inputs changed during proof'
 report['complete']=True;(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(w/'report.json')
if __name__=='__main__':main()
