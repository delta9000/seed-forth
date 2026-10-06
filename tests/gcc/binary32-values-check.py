#!/usr/bin/env python3
"""Binary32 scalar values and ABI, independently checked by host O0/O2 oracles.

All target compiler/object/linker bytes are Forth-built. Host compilers only
supply independent numerical and ABI observations. Run serially below 1 GiB.
"""
from pathlib import Path
import argparse,hashlib,json,resource,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
TEST=ROOT/'tests/gcc'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(cmd,status=0,**kw):
 p=subprocess.run([str(x) for x in cmd],capture_output=True,timeout=240,**kw)
 if p.returncode!=status:raise RuntimeError(f'{cmd}: exit {p.returncode}, expected {status}\n{p.stdout.decode(errors="replace")}{p.stderr.decode(errors="replace")}')
 return p

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--work',type=Path);a=ap.parse_args()
 resource.setrlimit(resource.RLIMIT_AS,(1073741824,1073741824))
 w=(a.work or Path(tempfile.mkdtemp(prefix='binary32-'))).resolve();w.mkdir(parents=True,exist_ok=True)
 paths=[ROOT/'seed-forth',ROOT/'010-lib.fth',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),ROOT/'tools/gcc-direct-cc.py',*sorted(TEST.glob('binary32-values*'))]
 hashes={str(p.relative_to(ROOT)):sha(p) for p in paths if p.is_file()}
 report={'compiler_and_test_sha256':hashes,'executions':[],'rejections':{}}
 fixture=(TEST/'binary32-values.c').read_text();(w/'oracle.c').write_text(fixture.replace('seed_','oracle_'))
 prototypes=['struct cell32 { unsigned int before;float value;unsigned int after; };']
 for line in fixture.splitlines():
  if 'seed_' in line and '(' in line and '{' in line:
   decl=line.split('{')[0].strip()+';';prototypes.extend([decl,decl.replace('seed_','oracle_')])
 (w/'binary32-prototypes.h').write_text('\n'.join(prototypes)+'\n')
 obj=w/'fixture.o';run([ROOT/'tools/gcc-direct-cc.py','-c',TEST/'binary32-values.c','-o',obj])
 for opt in ('-O0','-O2'):
  exe=w/('oracle'+opt)
  run(['gcc',opt,'-std=c99','-Wall','-Wextra','-Werror','-fno-fast-math','-ffp-contract=off','-fno-pie','-no-pie','-Wl,-z,noexecstack','-I'+str(w),TEST/'binary32-values-oracle.c',w/'oracle.c',obj,'-o',exe])
  p=run([exe]);print(p.stdout.decode().strip(),opt,flush=True)
  report['executions'].append({'name':'numerical and bidirectional ABI '+opt,'output':p.stdout.decode().strip(),'object_sha256':sha(obj),'executable_sha256':sha(exe)})
 exe=w/'forth-only'
 run([ROOT/'tools/gcc-direct-cc.py',obj,TEST/'binary32-values-main.c','-o',exe]);run([exe])
 report['executions'].append({'name':'Forth-only separate objects and linker','sha256':sha(exe)})
 print('PASS: Forth-only scalar binary32 conversions, rounding, ABI and varargs',flush=True)
 # Mixed conditionals have a dedicated execution/ABI gate; retain these
 # former rejection witnesses as positive compile regressions here.
 for name,body in {
  'mixed-ternary-int':'float f(int n,float x){return n?x:1;}',
  'mixed-ternary-double':'float f(int n,float x,double y){return n?x:y;}',
  # Former rejections: binary32 literals and static initializers are now
  # exact compile-time values (static-float-check.py checks their bytes).
  'float-suffix':'float f(void){return 1.25f;}',
  'float-suffix-uppercase':'float f(void){return 1.25F;}',
  'static-float':'float x=0;',
 }.items():
  src=w/(name+'.c');src.write_text(body+'\n');out=w/(name+'.o')
  run([ROOT/'tools/gcc-direct-cc.py','-c',src,'-o',out])
  report['executions'].append({'name':name+' accepted','object_sha256':sha(out)})
 rejects={
  'knr-float-parameter':('float f(x) float x; {return x;}',232),
  'knr-float-unused':('int f(x) float x; {return 0;}',232),
  'hexfloat':('float f(void){return 0x1p0;}',248),
  'long-double':('double f(long double x){return x;}',249),
  'float-index':('float f(float *x,float y){return x[y];}',232),
  'float-switch':('int f(float x){switch(x){case 1:return 1;}return 0;}',232),
  'float-remainder':('float f(float x,float y){return x%y;}',232),
  'float-shift':('float f(float x){return x<<1;}',232),
  'integer-shift-float':('int f(float x){return 1<<x;}',232),
  'float-complement':('float f(float x){return ~x;}',232),
  'float-bitwise':('float f(float x,float y){return x&y;}',232),
  'float-to-pointer':('void *f(float x){return (void *)x;}',232),
  'pointer-to-float':('float f(void *x){return (float)x;}',232),
  'float-record-abi':('struct A{float x;};void f(struct A x){}',232),
  'float-vararg-retrieval':('#include <stdarg.h>\nfloat f(int n,...){va_list ap;va_start(ap,n);return va_arg(ap,float);}',247),
 }
 for name,(body,status) in rejects.items():
  src=w/(name+'.c');src.write_text(body+'\n');out=w/(name+'.o')
  for existing in (False,True):
   out.unlink(missing_ok=True)
   if existing:out.write_bytes(b'previous-object\x00\xff')
   p=run([ROOT/'tools/gcc-direct-cc.py','-c',src,'-o',out],status)
   if existing:assert out.read_bytes()==b'previous-object\x00\xff'
   else:assert not out.exists()
  report['rejections'][name]=status
 print(f'PASS: {len(rejects)} unsupported boundaries preserve absent/existing output',flush=True)
 assert hashes=={str(p.relative_to(ROOT)):sha(p) for p in paths if p.is_file()},'inputs changed during proof'
 (w/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(w/'report.json')
if __name__=='__main__':main()
