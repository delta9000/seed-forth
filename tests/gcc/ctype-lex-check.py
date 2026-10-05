#!/usr/bin/env python3
"""Check measured lexer ctype functions on the complete valid argument domain."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='ctype-lex-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(args):
    r=subprocess.run(list(map(str,args)),capture_output=True,timeout=120)
    assert r.returncode==0,(args,r.returncode,r.stdout,r.stderr)
    return r
expected=[]
for c in range(-1,256):
    upper=65<=c<=90; lower=97<=c<=122; digit=48<=c<=57
    values=[c,int(upper or lower),int(upper or lower or digit),int(digit),int(32<=c<=126),int(c in [9,10,11,12,13,32]),int(upper),c+32 if upper else c,int(0<=c<=127),int(lower),int(digit or 65<=c<=70 or 97<=c<=102),c-32 if lower else c]
    values.extend([int(0<=c<32 or c==127),int(33<=c<=126),int(33<=c<=126 and not (upper or lower or digit))])
    expected.append(' '.join(map(str,values))+'\n')
expected=''.join(expected).encode()
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
source=ROOT/'tests/gcc/ctype-lex-check.c';production=OUT/'production'
run(CC+['-o',production,source]);r=run([production]);assert r.stdout==expected and not r.stderr
report={'compiler_source_identity':identity,'valid_argument_values':257,'isascii_arbitrary_int_and_function_addresses':True,'host_oracles':[]}
host=shutil.which('gcc')
if host:
    for level in ['-O0','-O2']:
        executable=OUT/('host'+level[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-D_DEFAULT_SOURCE',level,source,'-o',executable]);r=run([executable]);assert r.stdout==expected and not r.stderr
        report['host_oracles'].append(level)
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip()
names=['runtime/gcc-seed/ctype.c','runtime/gcc-seed/include/ctype.h','tests/gcc/ctype-lex-check.c','tests/gcc/ctype-lex-check.py']
report['source_sha256']={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names}
report['executable_sha256']=hashlib.sha256(production.read_bytes()).hexdigest()
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: 14 measured ctype functions, EOF and all 256 byte values, host O0/O2:',bool(host));print(OUT/'report.json')
