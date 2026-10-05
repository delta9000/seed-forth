#!/usr/bin/env python3
"""Qualified-void null provenance and saved-target qualifier regressions.

Host C90 O0/O2 determines validity. Direct compiler checks are bounded,
serial, and preserve absent/existing output on every rejection.
"""
from pathlib import Path
import argparse,hashlib,json,resource,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--work',type=Path);a=ap.parse_args()
 w=(a.work or Path(tempfile.mkdtemp(prefix='qualified-null-'))).resolve();w.mkdir(parents=True,exist_ok=True)
 resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
 paths=[ROOT/'seed-forth',ROOT/'010-lib.fth',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),ROOT/'tools/gcc-direct-cc.py',Path(__file__).resolve()]
 hashes={str(p.relative_to(ROOT)):sha(p) for p in paths};report={'input_sha256':hashes,'cases':{},'runs':[]}
 def save():(w/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 def run(cmd,expected=None):
  p=subprocess.run([str(c) for c in cmd],capture_output=True,text=True,timeout=120)
  report['runs'].append({'command':[str(c) for c in cmd],'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr});save()
  if expected is not None and p.returncode!=expected:raise RuntimeError(f'{cmd}: expected {expected}, got {p.returncode}\n{p.stderr}')
  return p
 prelude='struct S { int x; }; typedef const void CV; typedef const void *PCV; typedef void *P; typedef P const CP; typedef const int CI;\n'
 cases={}
 for cast in ['const void *','volatile void *','const volatile void *','CV *','PCV']:
  for operand in ['0','(int)0','(const int)0']:
   for reverse in [False,True]:
    zero='('+cast+')('+operand+')';expr=('c?p:'+zero) if reverse else ('c?'+zero+':p')
    name=('bad-'+cast+'-'+operand+'-'+str(reverse)).replace(' ','_').replace('*','ptr').replace('(','').replace(')','')
    cases[name]=(expr,False,238)
 for cast in ['void *const','void *volatile','CP']:
  for reverse in [False,True]:
   zero='('+cast+')0';expr=('c?p:'+zero) if reverse else ('c?'+zero+':p')
   name=('bounded-'+cast+'-'+str(reverse)).replace(' ','_').replace('*','ptr')
   cases[name]=(expr,True,238)
 for zero in ['(const int)0','(volatile int)0','(CI)0','(void*)(const int)0','(void*)(volatile int)0','(void*)(CI)0','(void*)(int)(const long)0']:
  for reverse in [False,True]:
   expr=('c?p:'+zero) if reverse else ('c?'+zero+':p')
   name=('valid-'+zero+'-'+str(reverse)).replace(' ','_').replace('*','ptr').replace('(','').replace(')','')
   cases[name]=(expr,True,0)
 for name,(expr,host_valid,expected) in cases.items():
  src=w/(name+'.c');reverse=expr.startswith('c?p:');active=1 if reverse else 0
  src.write_text(prelude+'int f(int c,struct S *p) { return ('+expr+')->x; }\nint main(void) { struct S s; s.x=42; return f('+str(active)+',&s); }\n')
  for opt in ['-O0','-O2']:
   exe=w/(name+opt);p=run(['gcc','-std=c90','-pedantic-errors',opt,src,'-o',exe])
   assert (p.returncode==0)==host_valid,(name,p.stderr)
   if host_valid:run([exe],42)
  obj=w/(name+'.o')
  for existing in ([False,True] if expected else [False]):
   obj.unlink(missing_ok=True)
   if existing:obj.write_bytes(b'previous-object\x00\xff')
   run([ROOT/'tools/gcc-direct-cc.py','-c',src,'-o',obj],expected)
   if expected:assert obj.read_bytes()==b'previous-object\x00\xff' if existing else not obj.exists()
  if not expected:
   exe=w/(name+'-mixed');run(['gcc','-no-pie',obj,'-o',exe],0);run([exe],42)
   exe=w/(name+'-forth');run([ROOT/'tools/gcc-direct-cc.py',src,'-o',exe],0);run([exe],42)
  report['cases'][name]={'source_sha256':sha(src),'host_valid':host_valid,'direct_status':expected,'absent_and_existing_output_preserved':bool(expected)};save()
  print('PASS:',name,flush=True)
 assert hashes=={str(p.relative_to(ROOT)):sha(p) for p in paths},'inputs changed'
 report['complete']=True;save();print(w/'report.json')
if __name__=='__main__':main()
