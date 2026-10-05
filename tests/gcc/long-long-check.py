#!/usr/bin/env python3
"""LP64 long long: distinct type, rank, constants, ABI and printf, GCC as oracle.

Programs are compiled by the Forth driver and run; host GCC (-std=gnu89
-U_FORTIFY_SOURCE) only builds the oracle and the opposite side of mixed
System V links. Negative cases reject with exact codes and preserve outputs.
Use unique --work paths; each child's address space is capped at 1GiB.
"""
from pathlib import Path
import argparse,hashlib,json,resource,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
TEST=ROOT/'tests/gcc'
HOST=['gcc','-std=gnu89','-U_FORTIFY_SOURCE','-w']
SYNTAX=['gcc','-std=gnu89','-U_FORTIFY_SOURCE','-pedantic-errors','-Wno-long-long','-fsyntax-only']
LIBIBERTY=ROOT/'build-out/stage-b-inputs/binutils-source'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
# name: (source, expected status). Every case is also invalid for host GCC.
NEGATIVE={
 'long-long-long':('long long long x;',233),
 'long-long-char':('long long char x;',233),
 'short-long-long':('short long long x;',233),
 'long-long-double':('long long double x;',233),
 'long-long-float':('float long long x;',233),
 'void-long-long':('long void long *x;',233),
 'signed-unsigned-long-long':('signed unsigned long long x;',233),
 'duplicate-int':('long long int int x;',233),
 'duplicate-unsigned':('unsigned long long unsigned x;',233),
 'function-long-vs-long-long':('long f(void); long long f(void);',237),
 'object-long-vs-long-long':('extern long v; extern long long v;',237),
 'object-ulong-vs-ullong':('extern unsigned long u; extern unsigned long long u;',237),
 'parameter-long-vs-long-long':('int f(long); int f(long long);',237),
 'conditional-pointer-mismatch':('void *f(int c,long *p,long long *q){return c?p:q;}',237),
 'typedef-mismatch':('typedef long long T; extern T t; extern long t;',237),
 'constant-overflow':('char a[9223372036854775807LL + 1];',242),
 'constant-shift-width':('char a[1LL << 64];',241),
 'constant-divide-overflow':('char a[(-9223372036854775807LL-1) / -1];',242),
 'constant-suffix-lll':('char a[1LLL];',240),
 'constant-suffix-mixed-case':('char a[1lL];',240),
 'constant-suffix-ulul':('char a[1ULUL];',240),
 # Runtime literals and #if share the constant evaluator's suffix parser.
 'runtime-suffix-lll':('long long f(void){return 1LLL;}',240),
 'runtime-suffix-mixed-case':('long f(long a){return a+1lL;}',240),
 'runtime-suffix-lul':('long f(void){long x;x=1LUL;return x;}',240),
 'runtime-suffix-uu':('unsigned f(void){return 1uu;}',240),
 'runtime-suffix-lll-lower':('long f(void){return 0x1lll;}',240),
 'runtime-suffix-ulu':('unsigned long f(void){return 1uLu;}',240),
 'initializer-suffix-lll':('long long x = 1LLL;',240),
 'constant-suffix-uu':('char a[1uu];',240),
 'constant-suffix-lul':('char a[1lul];',240),
 'pp-suffix-lll':('#if 1LLL\n#endif',240),
 'pp-suffix-uu':('#if 1uu\n#endif',240),
}
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--work',type=Path);a=ap.parse_args()
 w=(a.work or Path(tempfile.mkdtemp(prefix='long-long-'))).resolve();w.mkdir(parents=True,exist_ok=True)
 resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
 paths=[ROOT/'seed-forth',ROOT/'010-lib.fth',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),ROOT/'tools/gcc-direct-cc.py',
        ROOT/'runtime/gcc-seed/stdio.c',ROOT/'runtime/gcc-seed/include/limits.h',*sorted(TEST.glob('long-long*'))]
 hashes={str(p.relative_to(ROOT)):sha(p) for p in paths if p.is_file()}
 report={'compiler_and_test_sha256':hashes,'runs':[],'negative_cases':{}}
 def run(cmd,expected=0):
  p=subprocess.run([str(c) for c in cmd],capture_output=True,text=True,timeout=300)
  report['runs'].append({'command':[str(c) for c in cmd],'status':p.returncode,'stdout':p.stdout[-4000:],'stderr':p.stderr})
  (w/'report.json').write_text(json.dumps(report,indent=2)+'\n')
  if p.returncode!=expected:raise RuntimeError(f'{cmd}: expected {expected}, got {p.returncode}\n{p.stdout[-2000:]}{p.stderr}')
  return p
 direct=[ROOT/'tools/gcc-direct-cc.py'];inc=['-I',TEST]
 provider=TEST/'long-long.c';caller=TEST/'long-long-main.c'
 # Host oracle: both sides built by GCC, at two optimisation levels.
 expected=None
 for opt in ('-O0','-O2'):
  exe=w/('host'+opt);run([*HOST,opt,*inc,provider,caller,'-o',exe]);out=run([exe]).stdout
  if expected is None:expected=out
  elif out!=expected:raise RuntimeError('host oracle differs between -O0 and -O2')
 (w/'oracle.out').write_text(expected);print('PASS: host gnu89 oracle,',len(expected.splitlines()),'lines',flush=True)
 sfp=w/'sf-provider.o';sfc=w/'sf-caller.o'
 run([*direct,*inc,'-c',provider,'-o',sfp]);run([*direct,*inc,'-c',caller,'-o',sfc])
 exe=w/'forth-only';run([*direct,sfp,sfc,'-o',exe])
 if run([exe]).stdout!=expected:raise RuntimeError('Forth-only output differs from the oracle')
 print('PASS: Forth-only objects, linker and seed printf %lld/%llu/%llx/%llX/%llo',flush=True)
 for opt in ('-O0','-O2'):
  exe=w/('sf-provider-host-caller'+opt);run([*HOST,opt,'-no-pie',*inc,sfp,caller,'-o',exe])
  if run([exe]).stdout!=expected:raise RuntimeError('Forth provider with host caller differs '+opt)
  exe=w/('host-provider-sf-caller'+opt);run([*HOST,opt,'-no-pie',*inc,provider,sfc,'-o',exe])
  if run([exe]).stdout!=expected:raise RuntimeError('host provider with Forth caller differs '+opt)
  print('PASS: bidirectional System V INTEGER-class long long interop',opt,flush=True)
 spell=TEST/'long-long-spellings.c'
 run([*SYNTAX,spell])
 exe=w/'host-spellings';run([*HOST,spell,'-o',exe]);run([exe],42)
 exe=w/'sf-spellings';run([*direct,spell,'-o',exe]);run([exe],42)
 print('PASS: specifier orders, __extension__ positions and conversions',flush=True)
 for name,(body,status) in NEGATIVE.items():
  src=w/(name+'.c');src.write_text(body+'\n');obj=w/(name+'.o')
  host=subprocess.run([*SYNTAX,str(src)],capture_output=True,text=True,timeout=30)
  if host.returncode==0:raise RuntimeError(f'host GCC accepts negative case {name}')
  for existing in (False,True):
   obj.unlink(missing_ok=True)
   if existing:obj.write_bytes(b'previous object\x00\xff')
   run([*direct,'-c',src,'-o',obj],status)
   assert obj.read_bytes()==b'previous object\x00\xff' if existing else not obj.exists()
  report['negative_cases'][name]={'expected_status':status,'host_stderr':host.stderr,'absent_and_existing_output_preserved':True}
  print('PASS:',name,'rejects with',status,flush=True)
 lib=LIBIBERTY/'libiberty'
 if (lib/'strtoll.c').is_file():
  driver=TEST/'long-long-strtoll-main.c';flags=['-DHAVE_LONG_LONG','-DHAVE_LIMITS_H','-I',LIBIBERTY/'include']
  objs=[]
  for name in ('strtoll','strtoull','safe-ctype'):
   obj=w/(name+'.o');run([*direct,*flags,'-c',lib/(name+'.c'),'-o',obj]);objs.append(obj)
  exe=w/'host-strtoll';run([*HOST,*flags,driver,*(lib/(n+'.c') for n in ('strtoll','strtoull','safe-ctype')),'-o',exe])
  want=run([exe]).stdout
  exe=w/'sf-strtoll';run([*direct,driver,*objs,'-o',exe])
  if run([exe]).stdout!=want:raise RuntimeError('Forth-built libiberty strtoll/strtoull differ from host')
  print('PASS: original libiberty strtoll.c/strtoull.c built by Forth match host GCC',flush=True)
 else:print('SKIP: original libiberty strtoll check requires the pinned binutils source',flush=True)
 assert hashes=={str(p.relative_to(ROOT)):sha(p) for p in paths if p.is_file()},'inputs changed during proof'
 report['complete']=True;(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(w/'report.json')
if __name__=='__main__':main()
