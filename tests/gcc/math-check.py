#!/usr/bin/env python3
"""Build/execute exp/log with Forth only; host oracles are a separate command."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(command):
    result = subprocess.run(list(map(str, command)), capture_output=True, timeout=180)
    assert result.returncode == 0, (command, result.returncode, result.stdout, result.stderr)
    assert not result.stderr, (command, result.stderr)
    return result.stdout


def main():
    (ROOT/'build-out').mkdir(exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix='math-production-',dir=ROOT/'build-out'))
    compiler = [sys.executable, ROOT/'tools/gcc-direct-cc.py']
    identity = run(compiler+['--print-source-hash']).decode().strip()
    executable = out/'math-production'
    run(compiler+['-o',executable,ROOT/'tests/gcc/math-production.c','-lm'])
    data = run([executable])
    (out/'results.txt').write_bytes(data)
    records = [line.split() for line in data.decode().splitlines()]
    assert len(records) == 27089, len(records)
    # These bits/errno follow the public contract, not a host libm table.
    required = [
        ('0','0000000000000000','fff0000000000000','34'),
        ('0','8000000000000000','fff0000000000000','34'),
        ('0','8000000000000001','7ff8000000000000','33'),
        ('0','3ff0000000000000','0000000000000000','123'),
        ('0','7ff0000000000000','7ff0000000000000','123'),
        ('0','fff0000000000000','7ff8000000000000','33'),
        ('1','0000000000000000','3ff0000000000000','123'),
        ('1','8000000000000000','3ff0000000000000','123'),
        ('1','7ff0000000000000','7ff0000000000000','123'),
        ('1','fff0000000000000','0000000000000000','123'),
        ('1','7fefffffffffffff','7ff0000000000000','34'),
        ('1','ffefffffffffffff','0000000000000000','34'),
        ('1','c0874910d52d3052','0000000000000000','34'),
        ('1','c0874910d52d3051','0000000000000001','34'),
        ('1','40862e42fefa39f0','7ff0000000000000','34'),
    ]
    keys = {(op,xb,yb,error) for op,xb,count,yb,error in records}
    assert all(key in keys for key in required)
    for op,xb,count,yb,error in records:
        if (int(xb,16)&0x7fffffffffffffff)>0x7ff0000000000000:
            assert (int(yb,16)&0x7ff8000000000000)==0x7ff8000000000000 and error=='123'
    assert identity == run(compiler+['--print-source-hash']).decode().strip()
    files = ['runtime/gcc-seed/math.c','runtime/gcc-seed/include/math.h',
             'tests/gcc/math-production.c','tests/gcc/math-check.py']
    report = {'proof':'Forth C compiler and Forth linker; no host objects or library',
              'compiler_source_identity':identity,'records':len(records),
              'exact_contract_cases':len(required),
              'host_compiler':False,'host_linker':False,'host_libm':False,
              'numerical_oracle':'Separate math-oracle-check.py --production-output results.txt',
              'source_sha256':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in files},
              'artifact_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [executable,out/'results.txt']}}
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: Forth-only exp/log compilation, linkage, execution and exact special-value contracts')
    print(out/'report.json')
    print('Numerical validation command: python3 tests/gcc/math-oracle-check.py --production-output '+str(out/'results.txt'))


if __name__ == '__main__':
    main()
