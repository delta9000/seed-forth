#!/usr/bin/env python3
"""sscanf/fscanf %n: Forth-built fixture vs a host-glibc build (oracle only)."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'tests/gcc/scanf-count-check.c'


def main():
    (ROOT / 'build-out').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='scanf-count-', dir=ROOT / 'build-out'))
    production = work / 'scanf-count-forth'
    oracle = work / 'scanf-count-glibc'
    subprocess.run([sys.executable, ROOT / 'tools/gcc-direct-cc.py', FIXTURE, '-o', production], check=True)
    subprocess.run(['gcc', '-std=gnu89', '-O1', '-w', FIXTURE, '-o', oracle], check=True)
    outputs = [subprocess.run([program, work / (program.name + '.txt')], capture_output=True,
                              check=True, timeout=60).stdout for program in (production, oracle)]
    if outputs[0] != outputs[1]:
        raise SystemExit('FAIL: %n output differs\nseed:\n' + outputs[0].decode()
                         + 'glibc:\n' + outputs[1].decode())
    print(f'PASS: scanf %n, {outputs[0].count(b"\n")} lines identical to glibc ({work})')


if __name__ == '__main__':
    main()
