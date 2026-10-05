#!/usr/bin/env python3
"""Serial <=1 GiB fcntl gate, with Forth raw faults and independent GCC/libc oracles."""
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
OUT = Path(tempfile.mkdtemp(prefix='fcntl-check-', dir=ROOT / 'build-out'))
CC = [sys.executable, str(ROOT / 'tools/gcc-direct-cc.py')]
LIMIT = 1024 ** 3
PASSED = b'fcntl contracts passed\n'
FAULTS_PASSED = b'fcntl fault contracts passed\n'


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(args, **kwargs):
    command = [str(value) for value in args]
    result = subprocess.run(command, capture_output=True, timeout=300,
                            preexec_fn=limits, **kwargs)
    assert result.returncode == 0, (command, result.returncode, result.stdout, result.stderr)
    return result


def exercise(executable):
    directory = Path(tempfile.mkdtemp(prefix='files-', dir=OUT))
    # Descriptors 9 and 20-31 must start closed: close every inherited one but 0-2.
    result = run([executable, directory], input=b'', close_fds=True)
    assert result.stdout == PASSED and not result.stderr, (result.stdout, result.stderr)
    assert not list(directory.iterdir()), 'file leaked'
    return True


identity = run(CC + ['--print-source-hash']).stdout.decode().strip()
source = ROOT / 'tests/gcc/fcntl-check.c'
runtime = ROOT / 'runtime/gcc-seed/fcntl.c'
production = OUT / 'production'
run(CC + ['-o', production, source])
report = {'compiler_source_identity': identity, 'production_contracts_passed': exercise(production),
          'production_toolchain': 'unchanged 1772-byte seed; Forth preprocessing, compilation and linking',
          'close_on_exec_probe': 'raw fork/execve/wait4 test scaffolding; /bin/sh writes to descriptor 9',
          'memory_limit_bytes': LIMIT, 'parallel_jobs': 1, 'host_oracles': []}
renames = ['-Dfcntl=tested_fcntl', '-D__seed_syscall6=tested_fcntl_syscall']
fault_source = ROOT / 'tests/gcc/fcntl-faults.c'
fault_object = OUT / 'tested-fcntl.o'
run(CC + renames + ['-c', '-o', fault_object, runtime])
faults = OUT / 'faults'
run(CC + ['-o', faults, fault_source, fault_object])
result = run([faults])
assert result.stdout == FAULTS_PASSED and not result.stderr
report['scripted_faults'] = ['syscall 72 with exact descriptor/command and zero tail',
    'F_GETFD/F_GETFL forward zero, ignoring any supplied argument',
    'one int argument, sign-extended, for F_SETFD/F_SETFL/F_DUPFD/F_DUPFD_CLOEXEC',
    'exact -4095..-1 error range; -4096 unchanged; success preserves errno; EINTR not retried',
    'locks, ownership, signals, leases, notify, pipe size, seals and unknown commands: EINVAL, no syscall']
host = shutil.which('gcc')
assert host, 'GCC is required for independent O0/O2 host oracles'
for level in ['-O0', '-O2']:
    common = [host, '-std=c99', '-pedantic', '-Wall', '-Wextra', '-Werror', '-U_FORTIFY_SOURCE',
              '-D_GNU_SOURCE', level]
    oracle = OUT / ('host-libc-' + level[1:])
    run(common + ['-DFCNTL_HOST_ORACLE', source, '-o', oracle])
    public = exercise(oracle)
    host_object = OUT / ('host-runtime-' + level[1:] + '.o')
    run(common + renames + ['-idirafter', ROOT / 'runtime/gcc-seed/include', '-c',
                            runtime, '-o', host_object])
    host_faults = OUT / ('host-faults-' + level[1:])
    run(common + [fault_source, host_object, '-o', host_faults])
    result = run([host_faults])
    assert result.stdout == FAULTS_PASSED and not result.stderr
    report['host_oracles'].append({'optimization': level, 'libc_public_contract': public,
                                   'independently_compiled_runtime_faults': True})
binutils = options.binutils_source_root.resolve()
consumer = binutils / 'libiberty/pex-unix.c'
if consumer.is_file():
    configuration = OUT / 'libiberty-config'
    configuration.mkdir()
    (configuration / 'config.h').write_text(
        '/* Minimal hand-written stand-in; not a configure result. */\n'
        '#define HAVE_STDLIB_H 1\n#define HAVE_STRING_H 1\n#define HAVE_UNISTD_H 1\n'
        '#define HAVE_FCNTL_H 1\n#define HAVE_SYS_STAT_H 1\n#define HAVE_SYS_TYPES_H 1\n')
    destination = OUT / 'original-pex-unix.o'
    command = CC + ['-I', configuration, '-I', binutils / 'include', '-c', consumer,
                    '-o', destination]
    run(command)
    report['original_source_contract'] = {
        'source_sha256': hashlib.sha256(consumer.read_bytes()).hexdigest(),
        'command': list(map(str, command)),
        'scope': 'unchanged binutils 2.30 libiberty/pex-unix.c compiles; no link claim'}
else:
    print('SKIP: original pex-unix.c compile requires the pinned binutils source')
assert identity == run(CC + ['--print-source-hash']).stdout.decode().strip(), 'compiler changed'
names = ['runtime/gcc-seed/fcntl.c', 'runtime/gcc-seed/include/fcntl.h',
         'tests/gcc/fcntl-check.c', 'tests/gcc/fcntl-faults.c', 'tests/gcc/fcntl-check.py']
report['source_sha256'] = {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in names}
report['artifact_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in OUT.iterdir() if p.is_file()}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS: fcntl production, Forth raw faults, independent host O0/O2 libc/runtime oracles')
print(OUT / 'report.json')
