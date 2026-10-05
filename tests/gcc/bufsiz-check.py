#!/usr/bin/env python3
"""Check the advertised application block size through real stream I/O."""
from pathlib import Path
import hashlib,json,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2];(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='bufsiz-',dir=ROOT/'build-out'))
def run(args):
    r=subprocess.run(list(map(str,args)),capture_output=True,timeout=120)
    assert r.returncode==0,(args,r.returncode,r.stdout,r.stderr)
    return r
run([sys.executable,ROOT/'tools/gcc-direct-cc.py','-o',OUT/'production',ROOT/'tests/gcc/bufsiz-check.c'])
r=run([OUT/'production',OUT/'data']);assert r.stdout==b'8192\n' and not r.stderr
assert (OUT/'data').read_bytes()==bytes(range(256))*32
names=['runtime/gcc-seed/include/stdio.h','tests/gcc/bufsiz-check.c','tests/gcc/bufsiz-check.py']
report={'BUFSIZ':8192,'compile_time_array_bound':'pass','real_file_write_read_and_EOF':'pass','source_sha256':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names},'executable_sha256':hashlib.sha256((OUT/'production').read_bytes()).hexdigest()}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: BUFSIZ8192 real stream round trip');print(OUT/'report.json')
