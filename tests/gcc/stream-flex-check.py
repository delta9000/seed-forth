#!/usr/bin/env python3
"""Real Flex stream operations with independently calculated line partitions."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2];(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='stream-flex-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(args,**kw):
    r=subprocess.run(list(map(str,args)),capture_output=True,timeout=120,**kw)
    assert r.returncode==0,(args,r.returncode,r.stdout[-300:],r.stderr)
    return r
data=bytes(range(256))*2+b'tail';(OUT/'input').write_bytes(data)
expected=[]
for count in [2,3,7,32,129,300]:
    position=0
    while position<len(data):
        part=data[position:position+count-1]
        if b'\n' in part: part=part[:part.index(b'\n')+1]
        position+=len(part);expected.append(f'{count} {len(part)} {part.hex()}\n')
expected=''.join(expected).encode()
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
source=ROOT/'tests/gcc/stream-flex-check.c';production=OUT/'production'
run(CC+['-o',production,source])
def check(exe,label):
    directory=OUT/label;directory.mkdir()
    r=run([exe,OUT/'input',directory/'reopen',directory/'missing-parent'/'file',directory/'stdout',directory/'missing'],stdin=subprocess.DEVNULL)
    assert r.stdout==expected and not r.stderr,(label,r.stdout[-300:],r.stderr)
    assert (directory/'reopen').read_bytes()==b'hello\ntail'
    assert (directory/'stdout').read_bytes()==b'line\ntail'
    return hashlib.sha256(r.stdout).hexdigest()
report={'compiler_source_identity':identity,'line_partitions':len(expected.splitlines()),'production_output_sha256':check(production,'production-files'),'host_oracles':{}}
host=shutil.which('gcc')
if host:
    for level in ['-O0','-O2']:
        exe=OUT/('host'+level[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-D_POSIX_C_SOURCE=200809L','-DSTREAM_HOST_ORACLE',level,source,'-o',exe]);report['host_oracles'][level]=check(exe,'host-files'+level[1:])
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip()
names=['runtime/gcc-seed/stdio.c','runtime/gcc-seed/include/stdio.h','tests/gcc/stream-flex-check.c','tests/gcc/stream-flex-check.py']
report['source_sha256']={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: Flex stream group, real descriptor preservation,',report['line_partitions'],'line partitions; hostO0/O2:',bool(host));print(OUT/'report.json')
