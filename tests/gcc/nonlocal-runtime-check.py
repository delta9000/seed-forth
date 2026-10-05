#!/usr/bin/env python3
"""Forth-only nonlocal-return production proof, with opt-in host ABI oracles."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CC = [sys.executable, str(ROOT / 'tools/gcc-direct-cc.py')]
TEST = ROOT / 'tests/gcc'


def run(command, timeout=180):
    result = subprocess.run([str(x) for x in command], capture_output=True, timeout=timeout)
    if result.returncode:
        raise SystemExit(f'{command}: exit {result.returncode}\n'
                         + result.stdout.decode(errors='replace')
                         + result.stderr.decode(errors='replace'))
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--oracle', action='store_true', help='also run host C90 O0/O2 checks')
    args = parser.parse_args()
    (ROOT / 'build-out').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='nonlocal-runtime-', dir=ROOT / 'build-out'))
    identity = run(CC + ['--print-source-hash']).stdout.decode().strip()
    retained = work / 'returns-twice.o'
    fixture = work / 'nonlocal.o'
    run(CC + ['-c', TEST / 'sysv-setjmp.c', '-o', retained])
    run(CC + ['-c', TEST / 'nonlocal-runtime.c', '-o', fixture])
    production = work / 'production'
    run(CC + [retained, fixture, '-o', production])
    run([production], timeout=15)
    cache = ROOT / 'build-out/gcc-direct-cache' / identity
    manifest = json.loads((cache / 'manifest.json').read_text())
    runtime_objects = []
    for name in ('setjmp.o', 'longjmp.o'):
        source = cache / name
        data = source.read_bytes()
        assert data[:4] == b'\x7fELF' and int.from_bytes(data[16:18], 'little') == 1
        assert sha(source) == manifest['artifact_sha256'][name]
        destination = work / name
        shutil.copyfile(source, destination)
        runtime_objects.append(destination)
    assert manifest['host_compiler'] is False and manifest['host_linker'] is False
    assert '122-cc-sysv-runtime.fth' in manifest['source_sha256']
    assert 'runtime/gcc-seed/include/setjmp.h' in manifest['source_sha256']
    report = {'production_passed': True, 'compiler_source_identity': identity,
              'production_host_compiler': False, 'production_host_assembler': False,
              'production_host_linker': False, 'host_oracles': []}
    print('PASS: Forth-only nonlocal return, int values, recursive live frames, callbacks and stack reuse', flush=True)
    if args.oracle:
        host = shutil.which(os.environ.get('CC', 'cc'))
        if not host:
            raise SystemExit('requested host oracle requires CC or cc')
        include = work / 'host-include'
        include.mkdir()
        shutil.copyfile(ROOT / 'runtime/gcc-seed/include/setjmp.h', include / 'setjmp.h')
        for optimization in ('-O0', '-O2'):
            common = [host, '-std=c90', '-Wall', '-Wextra', '-fno-builtin',
                      '-fno-pie', '-no-pie', optimization]
            # Host caller -> Forth returns-twice code -> host callback ->
            # Forth longjmp, plus direct machine-register and stack checks.
            mixed = work / ('mixed' + optimization)
            run(common + ['-I', include,
                          TEST / 'nonlocal-runtime-host.c', TEST / 'nonlocal-runtime-abi.S',
                          TEST / 'sysv-setjmp-guard.S', retained, *runtime_objects, '-o', mixed])
            run([mixed], timeout=15)
            # Optimizing host-generated callers exercise returns_twice/noreturn
            # annotations against the real Forth runtime, not host libc.
            host_seed = work / ('host-seed' + optimization)
            run(common + ['-I', include, '-include', 'setjmp.h',
                          TEST / 'nonlocal-runtime.c', TEST / 'sysv-setjmp.c',
                          *runtime_objects, '-o', host_seed])
            run([host_seed], timeout=15)
            # Separate reference: the same C fixture with host headers/libc.
            reference = work / ('host-libc' + optimization)
            run(common + ['-DNONLOCAL_HOST_LIBC', TEST / 'nonlocal-runtime.c',
                          TEST / 'sysv-setjmp.c', '-o', reference])
            run([reference], timeout=15)
            report['host_oracles'].append({'optimization': optimization,
                'mixed_callbacks_and_machine_state': True,
                'host_callers_forth_runtime': True, 'host_libc_reference': True})
        print('PASS: separate host O0/O2 oracles, full-width callee saves, RSP/alignment and int upper bits')
    assert identity == run(CC + ['--print-source-hash']).stdout.decode().strip()
    report['artifacts'] = {p.name: sha(p) for p in work.iterdir() if p.is_file()}
    report['inputs'] = {name: sha(ROOT / name) for name in [
        '122-cc-sysv-runtime.fth', 'runtime/gcc-seed/include/setjmp.h',
        'tests/gcc/nonlocal-runtime.c', 'tests/gcc/nonlocal-runtime-check.py',
        'tests/gcc/nonlocal-runtime-abi.S', 'tests/gcc/nonlocal-runtime-host.c',
        'tests/gcc/sysv-setjmp.c', 'tests/gcc/sysv-setjmp-guard.S']}
    (work / 'report.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print('Report:', work / 'report.json')


if __name__ == '__main__':
    main()
