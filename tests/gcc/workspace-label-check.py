#!/usr/bin/env python3
"""Exercise mapped labels through the real direct compiler, serially."""
from pathlib import Path
import hashlib,json,resource,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
WORK=Path(tempfile.mkdtemp(prefix='workspace-labels-',dir=ROOT/'build-out'));records=[]
def compile(name,source,status=0,run=None):
 c=WORK/(name+'.c');c.write_text(source);out=WORK/name
 sentinel=b'preserve old output\n';out.write_bytes(sentinel)
 args=['python3',ROOT/'tools/gcc-direct-cc.py',c,'-o',out]
 p=subprocess.run(args,capture_output=True,timeout=180)
 assert p.returncode==status and not p.stdout,(name,p)
 if status:
  assert f'error {status}'.encode() in p.stderr and out.read_bytes()==sentinel,(name,p)
 else:
  assert not p.stderr,(name,p)
  if run is not None:
   p=subprocess.run([out],capture_output=True,timeout=10);assert (p.returncode,p.stdout,p.stderr)==(run,b'',b''),(name,p)
 records.append({'case':name,'status':status,'artifact_sha256':hashlib.sha256(out.read_bytes()).hexdigest()})
# Duplicate spelling is valid in another function and reused label rows must
# clear old vaddrs, switch depths and fixup chains. Include both directions.
source='''int one(void) { int x=0; goto second; first: x=x+1; return x; second: x=x+2; goto first; }
int two(void) { int x=0; goto second; first: x=x+3; return x; second: x=x+4; goto first; }
int main(void) { return one()!=3 || two()!=7; }
'''
compile('forward-backward-per-function-reset',source,run=0)
compile('duplicate-label','int main(void) { same: ; same: return 0; }\n',172)
compile('undefined-label','int main(void) { goto missing; return 0; }\n',174)
# A wide function forces old64 capacity, direct1024 exact boundary and reset.
for count in (65,1024,1025):
 body='int many(void) { int n=0; goto L0;\n'+''.join(f'L{i}: n=n+1; '+(f'goto L{i+1};' if i+1<count else 'return n;')+'\n' for i in range(count))+'}\n'
 body+='int again(void) { goto L0; L0: return 7; }\n'
 body+=f'int main(void) {{ return many()!={count} || again()!=7; }}\n'
 compile('labels-'+str(count),body,171 if count==1025 else 0,run=0 if count<=1024 else None)
(WORK/'report.json').write_text(json.dumps({'status':'PASS','cases':records},indent=2)+'\n')
print(f'PASS {len(records)} label cases: {WORK}/report.json')
