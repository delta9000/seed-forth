#!/usr/bin/env python3
"""Independent source-built nonlocal contexts and host memory-boundary checks."""
from pathlib import Path
import hashlib,json,subprocess,sys,tempfile,shutil
ROOT=Path(__file__).resolve().parents[2]
WORK=Path(tempfile.mkdtemp(prefix='review-nonlocal-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def run(command):
    p=subprocess.run([str(x) for x in command],capture_output=True,timeout=120)
    if p.returncode: raise RuntimeError((command,p.returncode,p.stdout,p.stderr))
    return p
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
source=ROOT/'tests/gcc/review-nonlocal-contexts.c'
exe=WORK/'production';run(CC+[source,'-o',exe]);run([exe])
cache=ROOT/'build-out/gcc-direct-cache'/identity
objects=[cache/'setjmp.o',cache/'longjmp.o']
manifest=json.loads((cache/'manifest.json').read_text())
assert not manifest['host_compiler'] and not manifest['host_linker']
for p in objects: assert sha(p)==manifest['artifact_sha256'][p.name]
include=WORK/'include';include.mkdir();shutil.copyfile(ROOT/'runtime/gcc-seed/include/setjmp.h',include/'setjmp.h')
report={'compiler_source_identity':identity,'production_passed':True,'production_host_target_tools':False,'host_oracles':[]}
for opt in ('-O0','-O2'):
    for name,src in (('contexts',source),('boundary',ROOT/'tests/gcc/review-nonlocal-boundary.c')):
        target=WORK/(name+opt)
        run(['cc','-std=c90','-Wall','-Wextra','-Werror','-fno-builtin','-fno-pie','-no-pie',opt,'-I',include,src,*objects,'-lm','-o',target]);run([target])
        report['host_oracles'].append({'name':name,'optimization':opt,'passed':True})
    reference=WORK/('host-libc'+opt)
    run(['cc','-std=c90','-Wall','-Wextra','-Werror',opt,source,'-o',reference]);run([reference])
    report['host_oracles'].append({'name':'contexts-host-libc-reference','optimization':opt,'passed':True})
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip()
report['artifacts']={p.name:sha(p) for p in WORK.iterdir() if p.is_file()}
report['sources']={str(p.relative_to(ROOT)):sha(p) for p in (source,ROOT/'tests/gcc/review-nonlocal-boundary.c',Path(__file__).resolve())}
report['leaf_objects']={p.name:sha(p) for p in objects}
(WORK/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print('PASS: independent dual live environments, expression statements, ancestor jumps, record-call abandonment, errno, exact page footprint/read-only restoration and ambient FP state')
print(WORK/'report.json')
