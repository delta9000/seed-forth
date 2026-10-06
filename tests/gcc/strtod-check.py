#!/usr/bin/env python3
"""Correctly rounded strtod/strtof/strtold/atof vs a host glibc oracle.

strtod-check.c generates its inputs from a seeded generator (with its own
exact decimal expander for half-way points) and prints result bits, errno
and end offsets. It is compiled by the Forth compiler against the seed
runtime and, separately, by host GCC against glibc, which is only the
expected-output oracle. Every section must print byte-identical lines.
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
FIXTURE = ROOT / 'tests/gcc/strtod-check.c'
# section, seed, count: 340,132 inputs at scale 1, each through strtod,
# atof and strtof (and strtold for every half-way extended80 point).
SECTIONS = [('special', 1, 0), ('decimal', 1, 200000), ('hex', 2, 100000), ('halfway', 3, 40000)]


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
    work = Path(options.work) if options.work else Path(tempfile.mkdtemp(prefix='strtod-', dir=ROOT / 'build-out'))
    work.mkdir(parents=True, exist_ok=True)
    production = work / 'strtod-forth'
    oracle = work / 'strtod-glibc'
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
            raise SystemExit(f'FAIL: strtod section {name} differs from glibc')
        sections[f'{name}:{seed}:{count}'] = {'lines': lines, 'sha256': hashlib.sha256(actual).hexdigest()}
        total += lines
    report = {'proof': 'Forth-built fixture output equals host-glibc-built fixture output',
              'host_objects_in_production': False, 'compared_lines': total, 'sections': sections,
              'fixture_sha256': hashlib.sha256(FIXTURE.read_bytes()).hexdigest()}
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS: correctly rounded strtod family, {total} inputs byte-identical to glibc ({work}/report.json)')


if __name__ == '__main__':
    main()
