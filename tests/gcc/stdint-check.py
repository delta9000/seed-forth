#!/usr/bin/env python3
"""Serial <=1 GiB <stdint.h> gate: Forth production versus host GCC/glibc facts."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import resource
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binutils-source-root', type=Path,
                    default=ROOT / 'build-out/stage-b-inputs/binutils-source')
options = parser.parse_args()
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='stdint-check-', dir=ROOT / 'build-out'))
CC = [sys.executable, str(ROOT / 'tools/gcc-direct-cc.py')]
INCLUDE = ROOT / 'runtime/gcc-seed/include'
LIMIT = 1024 ** 3


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(args):
    command = [str(value) for value in args]
    result = subprocess.run(command, capture_output=True, timeout=300, preexec_fn=limits,
                            env=dict(os.environ, LC_ALL='C'))
    assert result.returncode == 0 and not result.stderr, (command, result.returncode,
                                                          result.stdout[-2000:], result.stderr[-2000:])
    return result.stdout


identity = run(CC + ['--print-source-hash']).decode().strip()
source = ROOT / 'tests/gcc/stdint-check.c'
production = OUT / 'production'
run(CC + ['-o', production, source])
facts = run([production])
(OUT / 'production.txt').write_bytes(facts)
assert len(facts.splitlines()) == 96, facts
report = {'compiler_source_identity': identity, 'production_lines': 96,
          'production_toolchain': 'unchanged 1772-byte seed; Forth preprocessing, compilation and linking',
          'memory_limit_bytes': LIMIT, 'parallel_jobs': 1, 'host_oracles': []}
host = shutil.which('gcc')
assert host, 'GCC is required for the independent host glibc oracle'
strict = [host, '-std=c99', '-pedantic', '-Wall', '-Wextra', '-Werror', '-U_FORTIFY_SOURCE']
for level in ['-O0', '-O2']:
    oracle = OUT / ('host-glibc-' + level[1:])
    run(strict + [level, source, '-o', oracle])
    expected = run([oracle])
    (OUT / ('host-glibc-' + level[1:] + '.txt')).write_bytes(expected)
    assert expected == facts, 'Forth/runtime facts differ from host glibc at ' + level
    report['host_oracles'].append({'optimization': level, 'identical_output': True})
# The runtime headers alone, under host GCC: SAME() pointer initializers fail
# to compile unless each typedef names exactly the glibc LP64 type.
run(strict + ['-fno-builtin', '-nostdinc', '-I', INCLUDE, '-c', source,
              '-o', OUT / 'host-runtime-headers.o'])
report['host_runtime_header_type_identity'] = True
binutils = options.binutils_source_root.resolve()
obstack = binutils / 'libiberty/obstack.c'
if obstack.is_file():
    configuration = OUT / 'libiberty-config'
    configuration.mkdir()
    (configuration / 'config.h').write_text(
        '/* Minimal hand-written stand-in; not a configure result. */\n'
        '#define HAVE_STDLIB_H 1\n#define HAVE_STRING_H 1\n#define HAVE_SYS_TYPES_H 1\n')
    command = CC + ['-I', configuration, '-I', binutils / 'include', '-c', obstack,
                    '-o', OUT / 'original-obstack.o']
    run(command)
    report['original_source_contract'] = {
        'source_sha256': hashlib.sha256(obstack.read_bytes()).hexdigest(),
        'command': list(map(str, command)),
        'scope': 'unchanged binutils 2.30 libiberty/obstack.c compiles; no link claim'}
else:
    print('SKIP: original obstack.c compile requires the pinned binutils source')
assert identity == run(CC + ['--print-source-hash']).decode().strip(), 'compiler changed'
names = ['runtime/gcc-seed/include/stdint.h', 'runtime/gcc-seed/include/inttypes.h',
         'tests/gcc/stdint-check.c', 'tests/gcc/stdint-check.py']
report['source_sha256'] = {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in names}
report['artifact_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in OUT.iterdir() if p.is_file()}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS: stdint.h production facts match host glibc O0/O2; runtime header type identity')
print(OUT / 'report.json')
