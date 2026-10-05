#!/usr/bin/env python3
"""Serial <=1 GiB Forth descriptor I/O gate, with independent GCC/libc oracles."""
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

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--gcc-source-root', type=Path)
parser.add_argument('--gcc-libcpp-config', type=Path,
                    help='directory containing an original configure-generated config.h')
options = parser.parse_args()
if bool(options.gcc_source_root) != bool(options.gcc_libcpp_config):
    parser.error('provide both original GCC source root and libcpp configuration directory')
ROOT = Path(__file__).resolve().parents[2]
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='descriptor-io-check-', dir=ROOT / 'build-out'))
CC = [sys.executable, str(ROOT / 'tools/gcc-direct-cc.py')]

def limits():
    resource.setrlimit(resource.RLIMIT_AS, (1024 ** 3, 1024 ** 3))
    os.umask(0o027)

def run(args, **kwargs):
    command = [str(value) for value in args]
    result = subprocess.run(command, capture_output=True, timeout=180,
                            preexec_fn=limits, **kwargs)
    assert result.returncode == 0, (command, result.returncode, result.stdout, result.stderr)
    return result

def exercise(executable):
    directory = Path(tempfile.mkdtemp(prefix='files-', dir=OUT))
    (directory / 'file-link').symlink_to('file')
    result = run([executable, directory], input=b'')
    assert result.stdout in (b'descriptor I/O contracts passed; tmpfile=0\n',
                             b'descriptor I/O contracts passed; tmpfile=1\n'), result.stdout
    assert not result.stderr, result.stderr
    assert sorted(p.name for p in directory.iterdir()) == ['file-link'], 'file leaked'
    return {'contracts_passed': True, 'tmpfile_filesystem_supported': b'=1' in result.stdout}

identity = run(CC + ['--print-source-hash']).stdout.decode().strip()
source = ROOT / 'tests/gcc/descriptor-io-check.c'
production = OUT / 'production'
run(CC + ['-o', production, source])
report = {'compiler_source_identity': identity, 'production': exercise(production),
          'production_toolchain': 'unchanged 1772-byte seed; Forth preprocessing, compilation and linking',
          'memory_limit_bytes': 1024 ** 3, 'parallel_jobs': 1, 'host_oracles': []}
renames = ['-D' + name + '=tested_' + name for name in ['open', 'read', 'close', 'lseek']]
renames += ['-D__seed_syscall6=tested_descriptor_syscall']
fault_object = OUT / 'tested-descriptor-io.o'
run(CC + renames + ['-c', '-o', fault_object, ROOT / 'runtime/gcc-seed/descriptor-io.c'])
fault_source = ROOT / 'tests/gcc/descriptor-io-faults.c'
faults = OUT / 'faults'
run(CC + ['-o', faults, fault_source, fault_object])
result = run([faults])
assert result.stdout == b'descriptor I/O fault contracts passed\n' and not result.stderr
report['scripted_faults'] = ['exact syscall argument/register forwarding and zero tail',
    'two-argument open, mode_t unsigned promotion, integer literal mode, O_TMPFILE mode',
    'unsupported flags and incomplete O_TMPFILE rejected without syscall or va_arg',
    'single-call partial read, EOF, EINTR; no retry or hidden write',
    'close EINTR/EIO/EBADF is never retried',
    'exact -4095..-1 error range; -4096 unchanged; success preserves errno',
    '64-bit signed lseek argument and result; full-width read count']
host = shutil.which('gcc')
assert host, 'GCC is required for independent O0/O2 host oracles'
for level in ['-O0', '-O2']:
    common = [host, '-std=c90', '-pedantic', '-Wall', '-Wextra', '-Werror', '-D_GNU_SOURCE', level]
    oracle = OUT / ('host-libc-' + level[1:])
    run(common + ['-DDESCRIPTOR_IO_HOST_ORACLE', source, '-o', oracle])
    public = exercise(oracle)
    host_object = OUT / ('host-runtime-' + level[1:] + '.o')
    run(common + renames + ['-idirafter', ROOT / 'runtime/gcc-seed/include', '-c',
                           ROOT / 'runtime/gcc-seed/descriptor-io.c', '-o', host_object])
    host_fault = OUT / ('host-faults-' + level[1:])
    run(common + [fault_source, host_object, '-o', host_fault])
    result = run([host_fault])
    assert result.stdout == b'descriptor I/O fault contracts passed\n' and not result.stderr
    report['host_oracles'].append({'optimization': level, 'libc_public_contract': public,
                                   'independently_compiled_runtime_faults': True})
if options.gcc_source_root:
    source_root = options.gcc_source_root.resolve()
    configuration = options.gcc_libcpp_config.resolve()
    pins = json.loads((ROOT / 'tests/gcc/descriptor-io-source-pins.json').read_text())
    assert {name: hashlib.sha256((source_root / name).read_bytes()).hexdigest()
            for name in pins} == pins, 'original GCC consumer source pin mismatch'
    config_hash = hashlib.sha256((configuration / 'config.h').read_bytes()).hexdigest()
    source_contract = {'original_source_sha256': pins, 'config_h_sha256': config_hash,
                       'configuration_directory': str(configuration), 'commands': [],
                       'scope': 'Three unchanged complete consumer TUs compile; no configure or program-link claim'}
    include_flags = ['-I', source_root / 'libcpp', '-I', configuration,
                     '-I', source_root / 'include', '-I', source_root / 'libcpp/include']
    for name in pins:
        destination = OUT / ('original-' + Path(name).stem + '.o')
        command = CC + include_flags + ['-c', source_root / name, '-o', destination]
        run(command)
        source_contract['commands'].append(list(map(str, command)))
    assert config_hash == hashlib.sha256((configuration / 'config.h').read_bytes()).hexdigest()
    assert {name: hashlib.sha256((source_root / name).read_bytes()).hexdigest()
            for name in pins} == pins
    report['original_source_contract'] = source_contract
assert identity == run(CC + ['--print-source-hash']).stdout.decode().strip(), 'compiler changed'
names = ['runtime/gcc-seed/descriptor-io.c', 'runtime/gcc-seed/include/fcntl.h',
         'runtime/gcc-seed/include/unistd.h', 'runtime/gcc-seed/include/sys/types.h',
         'tests/gcc/descriptor-io-check.c', 'tests/gcc/descriptor-io-faults.c',
         'tests/gcc/descriptor-io-check.py', 'tests/gcc/descriptor-io-source-pins.json',
         'tests/gcc/check.sh']
report['source_sha256'] = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in names}
report['artifact_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in OUT.iterdir() if p.is_file()}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS: descriptor I/O production, Forth raw faults, independent host O0/O2 libc/runtime oracles')
print(OUT / 'report.json')
