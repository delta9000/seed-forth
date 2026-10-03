#!/usr/bin/env python3
"""Compile an unchanged pinned GCC header across source-location directives."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / 'tools/gcc-direct-cc.py'
PIN = '8d761202d371342ceff509b7a07cdbbf0ae767c03e3bd9abe57f35b9b15e6a73'
spec = importlib.util.spec_from_file_location('location_oracle', ROOT / 'tests/gcc/review-source-location-check.py')
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)


def run(args):
    result = subprocess.run(list(map(str, args)), capture_output=True, cwd=ROOT, timeout=90)
    assert result.returncode == 0, (args, result.returncode, result.stderr)
    return result.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--include', type=Path, default=ROOT / 'build-out/direct-gcc-inputs/gcc-source/include')
    args = ap.parse_args()
    header = args.include / 'ansidecl.h'
    assert hashlib.sha256(header.read_bytes()).hexdigest() == PIN, 'pinned original ansidecl.h required'
    work = Path(tempfile.mkdtemp(prefix='line-ansi-', dir=ROOT / 'build-out'))
    records = []
    for ending, suffix in [(b'\n', 'lf'), (b'\r\n', 'crlf')]:
        # The original header has an inert splice in a commented-out macro.
        # Exercise it beside both directive-prefix positions and mapped lines.
        data = (b'#line 40 "prefix.y"\n/* example #define X ' + bytes([92, 10]) +
                b' (x) */ #/**/define V __LINE__\nV __LINE__ __FILE__\n' +
                b'#/* continued ' + bytes([92, 10]) +
                b'comment */line 70 "after.y"\n__LINE__ __FILE__\n').replace(b'\n', ending)
        source = work / (suffix + '.c')
        source.write_bytes(data)
        actual = run([DRIVER, '-E', source])
        expected = run(['cc', '-E', '-P', source])
        assert oracle.tokens(actual) == oracle.tokens(expected), (suffix, actual, expected)
        records.append({'case': suffix, 'tokens_match': True})
    source = work / 'original-ansi.c'
    source.write_text('''#line 900 "outer.y"
#include "ansidecl.h"
#define VALUE __LINE__
static int after_header = __LINE__;
static const char logical_name[] = __FILE__;
PTR identity PARAMS ((PTR pointer));
PTR identity(PTR pointer) { return pointer; }
int main(void) {
  int value = 19;
  PTR pointer = &value;
  if (sizeof(PTR) != 8 || identity(pointer) != &value) return 1;
  if (after_header != 902 || VALUE != 910) return 2;
  if (logical_name[0] != 'o' || logical_name[6] != 'y' || logical_name[7] != 0) return 3;
  return 0;
}
''')
    actual = run([DRIVER, '-E', '-I', args.include, source])
    expected = run(['cc', '-E', '-P', '-std=c90', '-undef', '-ffreestanding', '-D__SEED_FORTH__=1', '-D__linux__=1', '-D__x86_64__=1', '-D__LP64__=1', '-nostdinc', '-I', args.include, source])
    assert oracle.tokens(actual) == oracle.tokens(expected), (actual, expected)
    (work / 'actual.i').write_bytes(actual)
    (work / 'host.i').write_bytes(expected)
    program = work / 'original-ansi'
    run([DRIVER, '-I', args.include, source, '-o', program])
    run([program])
    assert hashlib.sha256(header.read_bytes()).hexdigest() == PIN
    report = {'status': 'PASS', 'source_sha256': hashlib.sha256((ROOT / '040-cc-prep.fth').read_bytes()).hexdigest(), 'test_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'header_sha256': PIN, 'header_path': str(header.resolve()), 'cases': records, 'original_header': 'unchanged; host CPP token equivalence and Forth-built executable passed', 'compiler': 'seed/Forth preprocessing, compilation, runtime and linking'}
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: original GCC ansidecl.h, comment continuations, mapped locations and Forth execution')
    print(work / 'report.json')


if __name__ == '__main__':
    main()
