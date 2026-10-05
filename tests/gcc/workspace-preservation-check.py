#!/usr/bin/env python3
"""Compare against an explicitly frozen pre-workspace source tree, serially."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,resource,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--baseline',required=True,type=Path);a=p.parse_args()
ROOT=Path(__file__).resolve().parents[2];OLD=a.baseline.resolve()
resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
WORK=Path(tempfile.mkdtemp(prefix='workspace-preservation-',dir=ROOT/'build-out'))
sha=lambda b:hashlib.sha256(b).hexdigest()
assert (OLD/'seed-forth').read_bytes()==(ROOT/'seed-forth').read_bytes()
paths=['010-lib.fth']+[p.name for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')) if p.name not in ('120-cc-main.fth','140-cc-link.fth')]
vocabs=[b'\n'.join((r/n).read_bytes() for n in paths) for r in (OLD,ROOT)]
records=[]
def preserve(name,source,setup=b'',word=b'cc-parse-program',expected=0,stdout=b''):
 script=setup+b'\n: preserve cc-load-stdin cc-preprocess cc-out-init cc-globals-init cc-emit-elf-header '+word+b' cc-finalize-globals cc-finalize-elf [lit] 1 cc-out-buf cc-out-pos @ write drop bye ;\npreserve\n'
 products=[]
 for root,vocab in zip((OLD,ROOT),vocabs):
  r=subprocess.run([root/'seed-forth'],cwd=root,input=vocab+b'\n'+script+source,capture_output=True,timeout=90)
  assert r.returncode==0 and not r.stderr,(name,r)
  products.append(r.stdout)
 assert products[0]==products[1],name
 out=WORK/name;out.write_bytes(products[1]);out.chmod(0o700)
 r=subprocess.run([out],cwd=ROOT,capture_output=True,timeout=10)
 assert (r.returncode,r.stdout,r.stderr)==(expected,stdout,b''),(name,r)
 records.append({'case':name,'bytes':len(products[1]),'sha256':sha(products[1])})
for name,expected,stdout in [('P1-conditionals.c',63,b''),('P2-fn-macros.c',30,b''),('P3-casts.c',74,b''),('P8-libc-shims.c',42,b'ok\n')]:
 preserve('legacy-'+name,(ROOT/'tests/cc'/name).read_bytes(),expected=expected,stdout=stdout)
for name in ['basics','layout','stack-call','literals','many-args','switch-goto']:
 preserve('native-'+name,(ROOT/f'tests/tcc/native-{name}.c').read_bytes(),b'true cc-target-lp64 ! true cc-prep-direct ! [lit] 8388608 cc-arena-map',b'cc-native-program')
# Direct mapped versus old default-buffer artifacts, including a cold runtime link.
source=WORK/'small.c';source.write_text('#define A 3\n#if defined(A) && A * 7 == 21\nint main(void) { return 0; }\n#else\n#error bad mapped condition\n#endif\n')
identities=[];artifacts=[]
for root in (OLD,ROOT):
 def driver(*args):
  r=subprocess.run(['python3',root/'tools/gcc-direct-cc.py',*map(str,args)],capture_output=True,timeout=180)
  assert r.returncode==0 and not r.stderr,(root,args,r)
  return r
 identity=driver('--print-source-hash').stdout.decode().strip();identities.append(identity)
 prefix='old' if root==OLD else 'new'
 o=WORK/(prefix+'.o');exe=WORK/prefix
 driver('-c',source,'-o',o);driver(source,'-o',exe)
 artifacts.append((o.read_bytes(),exe.read_bytes()))
 r=subprocess.run([exe],capture_output=True,timeout=10);assert (r.returncode,r.stdout,r.stderr)==(0,b'',b'')
 manifest=json.loads((root/'build-out/gcc-direct-cache'/identity/'manifest.json').read_text())
 assert manifest['source_sha256']['tools/gcc-direct-cc.py']==sha((root/'tools/gcc-direct-cc.py').read_bytes())
 records.append({'case':prefix+'-direct-and-cache','identity':identity,'object_sha256':sha(o.read_bytes()),'exe_sha256':sha(exe.read_bytes())})
assert identities[0]!=identities[1]
assert artifacts[0]==artifacts[1],'direct emitted bytes changed'
(WORK/'report.json').write_text(json.dumps({'status':'PASS','baseline':str(OLD),'baseline_identity':identities[0],'candidate_identity':identities[1],'records':records},indent=2)+'\n')
print(f'PASS {len(records)} preservation cases: {WORK}/report.json')
