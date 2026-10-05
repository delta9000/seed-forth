#!/usr/bin/env python3
"""AMD64 float metadata, binary64 constants, and unsupported-value gates."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2];(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='float-header-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(args,okay=True):
    r=subprocess.run(list(map(str,args)),capture_output=True,timeout=120)
    if okay: assert r.returncode==0,(args,r.returncode,r.stdout,r.stderr)
    return r
expected=b'2\n24 6 -125 -37 128 38\n53 15 -1021 -307 1024 308\n64 18 -16381 -4931 16384 4932\n4 4 8 8 8 16 16 16 32\n'
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
source=ROOT/'tests/gcc/float-header-check.c';production=OUT/'production'
run(CC+['-o',production,source]);r=run([production]);assert r.stdout==expected and not r.stderr
report={'compiler_source_identity':identity,'metadata_and_binary64_bits':'pass','unsupported_typed_constants':{},'host_oracles':[]}
for name in ['FLT_MIN','FLT_MAX','FLT_EPSILON','LDBL_MIN','LDBL_MAX','LDBL_EPSILON']:
    probe=OUT/(name+'.c');probe.write_text('#include <float.h>\nint main(void) { return (int)'+name+'; }\n')
    r=run(CC+['-c','-o',OUT/(name+'.o'),probe],False)
    assert r.returncode!=0,(name,'unsupported value unexpectedly accepted')
    report['unsupported_typed_constants'][name]={'exit':r.returncode,'diagnostic':r.stderr.decode()}
host=shutil.which('gcc')
if host:
    names=[prefix+'_'+suffix for prefix in ['FLT','DBL','LDBL'] for suffix in ['MIN','MAX','EPSILON']]
    types={'FLT':'float','DBL':'double','LDBL':'long double'}
    definitions=OUT/'target-values.c';definitions.write_text('#include "'+str(ROOT/'runtime/gcc-seed/include/float.h')+'"\n'+''.join(types[n.split('_')[0]]+' target_'+n+'(void) { return '+n+'; }\n' for n in names))
    oracle=OUT/'host-values.c';oracle.write_text('#include <float.h>\n'+''.join(types[n.split('_')[0]]+' target_'+n+'(void);\n' for n in names)+'int main(void) {\n'+''.join('if (target_'+n+'() != '+n+') return '+str(i+1)+';\n' for i,n in enumerate(names))+'return 0; }\n')
    for level in ['-O0','-O2']:
        executable=OUT/('host'+level[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-DFLOAT_HOST_ORACLE',level,source,'-o',executable]);r=run([executable]);assert r.stdout==expected and not r.stderr
        executable=OUT/('values'+level[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror',level,definitions,oracle,'-o',executable]);run([executable]);report['host_oracles'].append(level)
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip()
names=['runtime/gcc-seed/include/float.h','tests/gcc/float-header-check.c','tests/gcc/float-header-check.py']
report['source_sha256']={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: target format/layout metadata, nine host limit values, binary64 bits, six unsupported value gates');print(OUT/'report.json')
