#!/usr/bin/env python3
"""Descriptor-backed fixed-array pointers: behavior, ABI and rejection gates."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--baseline-root',type=Path);a=ap.parse_args()
 work=Path(tempfile.mkdtemp(prefix='array-pointer-',dir=ROOT/'build-out'));events=[]
 env=dict(os.environ);env['PYTHONWARNINGS']="ignore:'maxsplit' is passed as positional argument:DeprecationWarning"
 def run(cmd,negative=False,**kw):
  p=subprocess.run(list(map(str,cmd)),env=env,capture_output=True,timeout=180,**kw)
  events.append({'command':list(map(str,cmd)),'status':p.returncode,'stderr':p.stderr.decode(errors='replace')})
  (work/'commands.json').write_text(json.dumps(events,indent=2)+'\n')
  assert (p.returncode!=0 if negative else p.returncode==0),events[-1]
  return p.stdout
 cc=[sys.executable,ROOT/'tools/gcc-direct-cc.py']
 for case in ['array-pointer','array-pointer-static','array-pointer-function-address','array-pointer-static-decay']:
  src=ROOT/'tests/gcc'/(case+'.c');out=work/case
  run(cc+[src,'-o',out]);run([out])
  for opt in ['-O0','-O2']:
   host=work/(case+opt);run(['gcc',opt,'-Wl,-z,noexecstack',src,'-o',host]);run([host])
 # Preserve descriptors through ellipsis and unspecified-prototype promotions.
 fixtures=[ROOT/'tests/gcc'/('array-pointer-varargs-'+name+'.c') for name in ('caller','provider')]
 objects=[work/('varargs-'+name+'.o') for name in ('caller','provider')]
 for source,obj in zip(fixtures,objects):run(cc+['-c',source,'-o',obj])
 executable=work/'varargs-descriptors';run(cc+objects+['-o',executable]);run([executable])
 for opt in ['-O0','-O2']:
  hosts=[]
  for source,name in zip(fixtures,('caller','provider')):
   obj=work/('varargs-host-'+name+opt+'.o');hosts.append(obj)
   run(['gcc','-std=gnu90',opt,'-fno-pie','-fno-stack-protector','-c',source,'-o',obj])
  for index in (0,1):
   exe=work/('varargs-mixed-'+str(index)+opt)
   run(['gcc','-no-pie','-Wl,-z,noexecstack',objects[index],hosts[1-index],'-o',exe]);run([exe])
 negative={
  'bound':'typedef long a[2];typedef long b[3];void f(a*);void f(b*);',
  'depth':'typedef long a[2];void f(a*);void f(a**);',
  'element':'typedef long a[2];typedef int b[2];void f(a*);void f(b*);',
  'init':'typedef long a[2];typedef long b[3];int main(void){a x={1,2};b *p=&x;return 0;}',
  'void':'typedef void a[2];a *p;',
  'function':'typedef int f(void);typedef f a[2];a *p;',
  'grouped-zero':'long (*p)[0];','grouped-inner-zero':'long (*p)[2][0];',
  'overflow':'long (*p)[1073741824];',
  'unsupported-grouped-array':'long (*p[2])[3];',
  'static-bound':'typedef int A[3];typedef int B[2];A a[2];B*p=a;',
  'static-element':'typedef int A[3];typedef long B[3];A a[2];B*p=a;',
  'static-depth':'typedef int A[3];A a[2];A**p=a;',
  'static-scalar':'typedef int A[3];A a[2];int*p=a;',
  'static-qualified':'typedef int A[3];const A a[2]={{1,2,3},{4,5,6}};A*p=a;',
  'static-conditional':'typedef int A[3];typedef int B[2];A a[2];B b[2];A*p=1?a:b;',
  'bad-add':'typedef long A[2];A*f(A*p,A*q){return p+q;}',
  'bad-sub-assign':'typedef long A[2];void f(A*p,A*q){p-=q;}',
  'bad-add-assign':'typedef long A[2];void f(A*p,A*q){p+=q;}',
  'bad-difference':'typedef long A[2];typedef long B[3];long f(A*p,B*q){return p-q;}',
  'bad-conditional':'typedef long A[2];typedef long B[3];A*f(A*p,B*q,int n){return n?p:q;}',
  'bad-integer':'typedef long A[2];void f(void){A*p=5;}',
  'unsupported-function-return':'long (*f(void))[3];',
 }
 for name,source in negative.items():
  src=work/(name+'.c');src.write_text(source+'\n');out=work/(name+'.o');old=b'existing complete object\n';out.write_bytes(old)
  run(cc+['-c',src,'-o',out],negative=True);assert out.read_bytes()==old,name
 if a.baseline_root:
  paths=[ROOT/'010-lib.fth']+[p for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')) if p.name not in ('120-cc-main.fth','140-cc-link.fth')]
  vocabs=[b'\n'.join((base/p.name).read_bytes() for p in paths) for base in (a.baseline_root,ROOT)]
  for native,names in [(False,['P1-conditionals','P2-fn-macros','P3-casts','P8-libc-shims']),(True,['basics','layout','stack-call','literals','many-args','switch-goto'])]:
   for name in names:
    src=(ROOT/('tests/tcc/native-'+name+'.c' if native else 'tests/cc/'+name+'.c')).read_bytes()
    setup=b'true cc-target-lp64 ! true cc-prep-direct ! [lit] 8388608 cc-arena-map\n' if native else b''
    parser=b'cc-native-program' if native else b'cc-parse-program'
    script=setup+b': preservation cc-load-stdin cc-preprocess cc-out-init cc-globals-init cc-emit-elf-header '+parser+b' cc-finalize-globals cc-finalize-elf [lit] 1 cc-out-buf cc-out-pos @ write drop bye ;\npreservation\n'
    outputs=[run([ROOT/'seed-forth'],input=v+b'\n'+script+src,cwd=ROOT) for v in vocabs];assert outputs[0]==outputs[1],name
 print('PASS: array pointers, grouped type names, static addresses, bounded rejections and optional legacy/native byte preservation')
 print(work/'commands.json')
if __name__=='__main__':main()
