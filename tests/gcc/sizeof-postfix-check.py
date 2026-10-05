#!/usr/bin/env python3
"""`sizeof (expr)` with postfix operators: Forth production, host oracles.

Reduced from binutils 2.30 bfd/peicode.h, whose `ARRAY_SIZE (jtab)` gives
`sizeof (jtab) / sizeof (jtab)[0]` (formerly error 96).  Host GCC
(-std=gnu89 -U_FORTIFY_SOURCE, -O0/-O2) is an oracle only.
"""
from pathlib import Path
import hashlib, json, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'tests/gcc/sizeof-postfix.c'
EXPECTED = b'1 24 3 7\n5 8 1 28 4\n8 48 4\n4 4\n'


def run(command, expected=0):
    p = subprocess.run([str(c) for c in command], capture_output=True, timeout=180)
    assert p.returncode == expected, (command, p.returncode, p.stderr.decode(errors='replace'))
    return p.stdout


def main():
    (ROOT / 'build-out').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='sizeof-postfix-', dir=ROOT / 'build-out'))
    forth = work / 'forth'
    run([sys.executable, ROOT / 'tools/gcc-direct-cc.py', SOURCE, '-o', forth])
    output = run([forth])
    assert output == EXPECTED, output
    for opt in ('-O0', '-O2'):
        host = work / ('host' + opt)
        run(['gcc', '-std=gnu89', '-U_FORTIFY_SOURCE', opt, '-w', SOURCE, '-o', host])
        assert run([host]) == output, opt
    (work / 'report.json').write_text(json.dumps({
        'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'output': output.decode()}, indent=2) + '\n')
    print('PASS: sizeof (expr) postfix operands match host GCC -O0/-O2')


if __name__ == '__main__':
    main()
