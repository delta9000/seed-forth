#!/usr/bin/env python3
"""Real Forth-built Linux directory traversal and separate syscall-fault tests."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='dirent-check-',dir=ROOT/'build-out'))
commands=[]
def run(args,code=0):
    p=subprocess.run(list(map(str,args)),capture_output=True,timeout=180)
    commands.append({'arguments':list(map(str,args)),'returncode':p.returncode,
                     'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace')})
    (OUT/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    assert p.returncode==code,(args,p.returncode,p.stderr)
    assert not p.stderr,(args,p.stderr)
    return p.stdout
cc=[sys.executable,ROOT/'tools/gcc-direct-cc.py']
for stem in ('dirent-check','dirent-fault-check'):
    run(cc+[ROOT/'tests/gcc'/f'{stem}.c','-o',OUT/stem])
assert run([OUT/'dirent-fault-check'])==b'directory fault checks passed\n'
d=OUT/'entries';d.mkdir();names=['entry-%05d'%i for i in range(3000)]+['L'*255]
for name in names:(d/name).touch()
expected=sorted(names+['.','..'])
assert sorted(run([OUT/'dirent-check',d]).decode().splitlines())==expected
assert run([OUT/'dirent-check',d/'missing'],3)==b'open:2\n'
assert run([OUT/'dirent-check',d/names[0]],3)==b'open:20\n'
# Host references are independent; never used to build production artifacts.
oracle_headers=OUT/'oracle-headers';oracle_headers.mkdir()
for name in ('dirent.h','seed-syscall.h','seed-directory.h'):
    shutil.copy2(ROOT/'runtime/gcc-seed/include'/name,oracle_headers/name)
for opt in ('-O0','-O2'):
    host=OUT/('host-directory'+opt)
    run(['gcc',opt,'-std=c90','-pedantic',ROOT/'tests/gcc/dirent-check.c','-o',host])
    assert sorted(run([host,d]).decode().splitlines())==expected
    fault=OUT/('host-fault'+opt)
    run(['gcc',opt,'-std=c90','-pedantic','-I'+str(oracle_headers),
         ROOT/'tests/gcc/dirent-fault-check.c','-o',fault])
    assert run([fault])==b'directory fault checks passed\n'
print('PASS directory: 3003 entries, 255-byte real name, 492-byte synthetic name, refill/EOF/errors, 200 reopen cycles, malformed records, allocation/close/EINTR faults; GCC O0/O2 oracles')
print(OUT)
