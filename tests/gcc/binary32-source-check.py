#!/usr/bin/env python3
"""Replay the full, unchanged GCC 4.0.4 ggc-page.c using a recorded configuration.

This is a translation-unit compilation proof, not a complete GCC executable,
configuration regeneration, same-epoch bootstrap, or runtime execution proof.
"""
from pathlib import Path
import argparse,hashlib,json,os,resource,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
SOURCE_SHA='8612279163b9823b5832e12231384cd6cea9b74df0f6f96a054c54d17b769738'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument('--source-root',type=Path,required=True)
 ap.add_argument('--build-root',type=Path,required=True)
 ap.add_argument('--configuration-compiler-identity',required=True)
 ap.add_argument('--work',type=Path,required=True)
 a=ap.parse_args();s=a.source_root.resolve();b=a.build_root.resolve();w=a.work.resolve();w.mkdir(parents=True,exist_ok=True)
 resource.setrlimit(resource.RLIMIT_AS,(1073741824,1073741824))
 source=s/'gcc/ggc-page.c';assert sha(source)==SOURCE_SHA,'original source hash differs'
 paths=[ROOT/'seed-forth',ROOT/'010-lib.fth',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),ROOT/'tools/gcc-direct-cc.py',*sorted((ROOT/'runtime/gcc-seed').rglob('*'))]
 hashes={str(p.relative_to(ROOT)):sha(p) for p in paths if p.is_file()}
 headers={str(p.relative_to(b)):sha(p) for p in sorted(b.rglob('*.h')) if p.is_file()}
 assert headers,'configured/generated header evidence is required'
 driver=ROOT/'tools/gcc-direct-cc.py'
 identity=subprocess.check_output(['python3',str(driver),'--print-source-hash'],text=True).strip()
 cmd=['python3',str(driver),'-c','-DIN_GCC','-DHAVE_CONFIG_H','-I.','-I'+str(s/'gcc'),'-I'+str(s/'include'),'-I'+str(s/'libcpp/include'),str(source),'-o',str(w/'ggc-page.o')]
 start=time.monotonic();status=None;timed_out=False
 with (w/'stdout').open('wb') as out,(w/'stderr').open('wb') as err:
  try:status=subprocess.run(cmd,cwd=b,stdout=out,stderr=err,timeout=240,env={**os.environ,'TZ':'UTC0','LC_ALL':'C'}).returncode
  except subprocess.TimeoutExpired:timed_out=True
 report={'source_revision':'944765863eec87a9f37e297994fd2af960397138','source_sha256':SOURCE_SHA,'configuration_compiler_identity':a.configuration_compiler_identity,'candidate_compiler_identity':identity,'compiler_sha256':hashes,'configuration_header_sha256':headers,'command':cmd,'cwd':str(b),'status':status,'timed_out':timed_out,'elapsed_seconds':time.monotonic()-start,'diagnostic':(w/'stderr').read_text(),'object_sha256':sha(w/'ggc-page.o') if status==0 else None,'scope':__doc__}
 (w/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
 assert sha(source)==SOURCE_SHA
 assert headers=={str(p.relative_to(b)):sha(p) for p in sorted(b.rglob('*.h')) if p.is_file()},'configuration changed during proof'
 assert hashes=={str(p.relative_to(ROOT)):sha(p) for p in paths if p.is_file()},'compiler changed during proof'
 assert status==0 and not timed_out,report['diagnostic']
 print('PASS: full unchanged original GCC4 ggc-page.c compiles with separately identified configuration');print(w/'report.json')
if __name__=='__main__':main()
