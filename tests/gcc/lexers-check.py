#!/usr/bin/env python3
"""Replay the pinned parser-generator chain when its offline archives exist."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PIN = json.loads((ROOT / 'gcc-direct/lexer-inputs/sources.json').read_text())
FLEX = PIN['archives'][2]['directory']
EXPECTED = {
    'sources/heirloom-devtools-070527/lex/parser.c': '55208c65ca02c4302bdf6f33436929f3b1a7eb661ba7b7e9295b64a967026e48',
    'sources/heirloom-devtools-070527/lex/libl.a': 'd5a855998abc0a3bbb84a714b49d0dbf1e507910f528711b55aca16d07694212',
    'sources/' + FLEX + '/parse.c': '5980aebea45cf6a6a5680d5edb975a84702240b1968cff6e46bd4658fb9c02b4',
    'sources/' + FLEX + '/scan.c': '4cb3e1ce267d106449d734cec1a48d2b4213522f1f781c2591a918e028bd2a53',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, default=Path(os.environ.get(
        'GCC_LEXER_INPUTS', ROOT / 'build-out/lexer-inputs')))
    parser.add_argument('--work', type=Path, help='new recipe output directory')
    args = parser.parse_args()
    missing = [p['archive'] for p in PIN['archives']
               if not (args.inputs / 'archives' / p['archive']).is_file()]
    if missing:
        print('SKIP: pinned lexer archives unavailable: ' + ', '.join(missing))
        return 77
    if args.work:
        work = args.work.resolve()
    else:
        (ROOT / 'build-out').mkdir(exist_ok=True)
        work = Path(tempfile.mkdtemp(prefix='lexers-check-', dir=ROOT / 'build-out')) / 'work'
    subprocess.run([sys.executable, ROOT / 'gcc-direct/lexers.py', args.inputs.resolve(), work], check=True)
    report = json.loads((work / 'report.json').read_text())
    for name, expected in EXPECTED.items():
        actual = hashlib.sha256((work / name).read_bytes()).hexdigest()
        assert actual == expected, (name, actual, expected)
        assert report['sha256'][name] == actual, ('report hash differs', name)
    for name, digest in report['sha256'].items():
        assert hashlib.sha256((work / name).read_bytes()).hexdigest() == digest, name
    print('PASS: Forth-built oyacc -> Heirloom lex/libl.a -> flex; four known-good hashes match')
    print(work / 'report.json')
    return 0


if __name__ == '__main__':
    sys.exit(main())
