#!/usr/bin/env python3
"""Forth-built ASCII wide I/O, independent expected bytes and host libc oracles."""
from pathlib import Path
import hashlib, json, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[2]
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='wide-stdio-', dir=ROOT / 'build-out'))
CC = [sys.executable, str(ROOT / 'tools/gcc-direct-cc.py')]
def run(args):
    r = subprocess.run(list(map(str,args)), capture_output=True, timeout=120)
    assert r.returncode == 0, (args,r.returncode,r.stdout[-200:],r.stderr)
    return r
expected = []
def record(data,capacity):
    buffer = bytearray(b'X' * 64)
    if capacity:
        count = min(len(data),capacity-1)
        buffer[:count] = data[:count]
        buffer[count] = 0
    expected.append(f'{len(data)} {buffer.hex()}\n')
for text in [b'',b'abc',b'A\x7f\tz']:
    for width in [-9,0,2,9]:
        for precision in [-1,0,1,3,9]:
            field = text if precision < 0 else text[:precision]
            field = field.ljust(abs(width),b' ') if width < 0 else field.rjust(width,b' ')
            for capacity in [0,1,2,4,12,64]: record(b'['+field+b']',capacity)
for character in [0,32,65,127]:
    for width in [-9,0,2,9]:
        field = bytes([character])
        field = field.ljust(abs(width),b' ') if width < 0 else field.rjust(width,b' ')
        for capacity in [0,1,2,4,12,64]: record(b'['+field+b']',capacity)
expected = ''.join(expected).encode() + b'wide streams passed\n'
identity = run(CC+['--print-source-hash']).stdout.decode().strip()
for name,data in [('ascii',bytes(range(128))),('bad80',b'\x80'),('badff',b'\xff')]: (OUT/name).write_bytes(data)
source = ROOT/'tests/gcc/wide-stdio-check.c'
production = OUT/'production'
run(CC+['-o',production,source])
def check(executable,label):
    target = OUT/(label+'-output')
    r = run([executable,OUT/'ascii',OUT/'bad80',OUT/'badff',target])
    assert r.stdout == expected and not r.stderr, (label,r.stdout[-200:],r.stderr)
    assert target.read_bytes() == b'[    ab][Q  ]', (label,target.read_bytes())
    return {'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'executable_sha256':hashlib.sha256(executable.read_bytes()).hexdigest()}
report = {'compiler_source_identity':identity,'format_cases':456,'stream_ascii_values':128,'invalid_stream_bytes':[128,255],'production':check(production,'production'),'host_oracles':{}}
host = shutil.which('gcc')
if host:
    for level in ['-O0','-O2']:
        executable = OUT/('host'+level[1:])
        run([host,'-std=c99','-pedantic','-Wall','-Wextra','-Werror','-DWIDE_HOST_ORACLE',level,source,'-o',executable])
        report['host_oracles'][level] = check(executable,level[1:])
assert identity == run(CC+['--print-source-hash']).stdout.decode().strip(), 'compiler changed during check'
names = ['runtime/gcc-seed/stdio.c','runtime/gcc-seed/include/stdio.h','runtime/gcc-seed/include/wchar.h','tests/gcc/wide-stdio-check.c','tests/gcc/wide-stdio-check.py']
report['source_sha256'] = {n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: 456 wide-format cases, real ASCII/invalid/EOF streams, precision boundary; host O0/O2:',bool(host))
print(OUT/'report.json')
