#!/usr/bin/env python3
"""Exact floating printf: Forth-built production vs host glibc output oracle.

printf-float-check.c is compiled by the Forth compiler against the seed
runtime and, separately, by host GCC against glibc. glibc is only the
expected-output oracle; no host object reaches the production executable.
Every section must print byte-identical lines in both builds.
Use --scale N to multiply the randomized section sizes (stress runs).
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'tests/gcc/printf-float-check.c'
# section, seed, count: about 1.3 million compared lines at scale 1.
SECTIONS = [('large', 1, 0), ('flags', 1, 0), ('random', 1, 400000), ('random', 2, 400000),
            ('precision', 3, 1500), ('ties', 4, 4000), ('long', 5, 4000)]


def run(command, timeout=1800):
    result = subprocess.run([str(part) for part in command], capture_output=True, timeout=timeout)
    if result.returncode != 0:
        raise SystemExit(f'FAIL: {command}: status {result.returncode}\n{result.stderr.decode(errors="replace")}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--scale', type=int, default=1)
    parser.add_argument('--work')
    options = parser.parse_args()
    (ROOT / 'build-out').mkdir(exist_ok=True)
    work = Path(options.work) if options.work else Path(tempfile.mkdtemp(prefix='printf-float-', dir=ROOT / 'build-out'))
    work.mkdir(parents=True, exist_ok=True)
    production = work / 'printf-float-forth'
    oracle = work / 'printf-float-glibc'
    run([sys.executable, ROOT / 'tools/gcc-direct-cc.py', FIXTURE, '-o', production])
    run(['gcc', '-std=gnu89', '-O1', '-w', '-fno-builtin', FIXTURE, '-o', oracle])
    total = 0
    sections = {}
    for name, seed, count in SECTIONS:
        count = count * options.scale
        seed = seed + 1000 * (options.scale - 1)
        expected = run([oracle, name, seed, count])
        actual = run([production, name, seed, count])
        lines = expected.count(b'\n')
        if actual != expected:
            want = expected.splitlines()
            got = actual.splitlines()
            shown = 0
            for index in range(max(len(want), len(got))):
                left = want[index] if index < len(want) else b'<missing>'
                right = got[index] if index < len(got) else b'<missing>'
                if left != right:
                    print(f'{name} line {index + 1}:\n  glibc: {left!r}\n  seed:  {right!r}')
                    shown += 1
                    if shown == 10:
                        break
            raise SystemExit(f'FAIL: printf floating section {name} differs from glibc')
        sections[f'{name}:{seed}:{count}'] = {'lines': lines, 'sha256': hashlib.sha256(actual).hexdigest()}
        total += lines
    report = {'proof': 'Forth-built fixture output equals host-glibc-built fixture output',
              'host_objects_in_production': False, 'compared_lines': total, 'sections': sections,
              'fixture_sha256': hashlib.sha256(FIXTURE.read_bytes()).hexdigest()}
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS: exact floating printf, {total} lines byte-identical to glibc ({work}/report.json)')


if __name__ == '__main__':
    main()
