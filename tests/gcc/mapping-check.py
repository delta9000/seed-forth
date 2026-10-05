#!/usr/bin/env python3
"""Serial Linux AMD64 mapping proof; sparse files are never read wholesale."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import resource
import shutil
import signal
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--gcc-source', type=Path)
parser.add_argument('--gcc-config', type=Path)
args = parser.parse_args()
assert bool(args.gcc_source) == bool(args.gcc_config), 'supply source and configuration together'
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='mapping-', dir=ROOT / 'build-out'))
LIMIT = 1024 ** 3
resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
CC = [sys.executable, ROOT / 'tools/gcc-direct-cc.py']
commands = []

def sha(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for part in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(part)
    return value.hexdigest()

def run(command, expected=0, cwd=ROOT):
    command = list(map(str, command))
    result = subprocess.run(command, cwd=cwd, capture_output=True, timeout=300,
                            env=dict(os.environ, LC_ALL='C'))
    index = len(commands)
    (OUT / ('command-%02d.stdout' % index)).write_bytes(result.stdout)
    (OUT / ('command-%02d.stderr' % index)).write_bytes(result.stderr)
    commands.append({'command': command, 'cwd': str(cwd), 'status': result.returncode,
                     'expected': expected, 'stdout': result.stdout.decode(errors='replace'),
                     'stderr': result.stderr.decode(errors='replace')})
    (OUT / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    assert result.returncode == expected and not result.stderr, commands[-1]
    return result.stdout

identity = run(CC + ['--print-source-hash']).decode().strip()
preserved = {str(p.relative_to(ROOT)): sha(p) for p in
             [ROOT / 'seed-forth', ROOT / '000-seed.hex0', ROOT / 'runtime/gcc-seed/alloc.c']
             + sorted(ROOT.glob('*.fth'))}
assert (ROOT / 'seed-forth').stat().st_size == 1772
assert preserved['seed-forth'] == '697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e'
sparse = OUT / 'sparse.bin'
high = 2 ** 32 + 4096
with sparse.open('wb') as stream:
    for offset, byte in ((0, b'A'), (4096, b'B'), (high, b'H'), (high + 4096, b'T')):
        stream.seek(offset)
        stream.write(byte)
assert sparse.stat().st_size == high + 4097
assert sparse.stat().st_blocks * 512 < 1024 * 1024
fixture = ROOT / 'tests/gcc/mapping-check.c'
faults = ROOT / 'tests/gcc/mapping-faults.c'
runtime = ROOT / 'runtime/gcc-seed/mapping.c'
bridge = ROOT / 'tests/gcc/mapping-host.c'
include = ROOT / 'runtime/gcc-seed/include'
production = OUT / 'forth-production'
run(CC + [fixture, '-o', production])
wanted = b'mapping real-kernel contracts passed\n'
assert run([production, sparse]) == wanted
for mode in ('none', 'readonly', 'unmapped'):
    run([production, sparse, mode], expected=-signal.SIGSEGV)
elf = production.read_bytes()
assert elf[:5] == b'\x7fELF\x02'
phoff = int.from_bytes(elf[32:40], 'little')
phsize = int.from_bytes(elf[54:56], 'little')
phcount = int.from_bytes(elf[56:58], 'little')
assert all(int.from_bytes(elf[phoff + i * phsize:phoff + i * phsize + 4], 'little') not in (2, 3)
           for i in range(phcount)), 'production must have no interpreter or dynamic segment'
rename = ['-Dmmap=tested_mmap', '-Dmunmap=tested_munmap']
obj = OUT / 'forth-mapping.o'
run(CC + rename + ['-c', runtime, '-o', obj])
fault_obj = OUT / 'forth-mapping-fault.o'
run(CC + rename + ['-D__seed_syscall6=mapping_fake', '-c', runtime, '-o', fault_obj])
fault_exe = OUT / 'forth-faults'
run(CC + [faults, fault_obj, '-o', fault_exe])
assert run([fault_exe]) == b'mapping fault contracts passed\n'
host = shutil.which('gcc')
assert host, 'independent host GCC is required for this oracle gate'
flags = ['-std=c90', '-pedantic', '-Wall', '-Wextra', '-Werror', '-fno-builtin',
         '-D_GNU_SOURCE', '-no-pie', '-Wl,-z,noexecstack']
for opt in ('-O0', '-O2'):
    source_obj = OUT / ('host-source' + opt + '.o')
    run([host, opt] + flags + ['-fno-pie', '-fno-stack-protector', '-I' + str(include)]
        + rename + ['-c', runtime, '-o', source_obj])
    for mode, extra in (
        ('libc', ['-DMAPPING_LIBC']),
        ('forth-object', ['-DMAPPING_INTEROP', obj]),
        ('host-source', ['-DMAPPING_INTEROP', source_obj]),
    ):
        binary = OUT / (mode + opt)
        run([host, opt] + flags + ['-DMAPPING_HOST', fixture, bridge] + extra + ['-o', binary])
        assert run([binary, sparse]) == wanted
        for fault in ('none', 'readonly', 'unmapped'):
            run([binary, sparse, fault], expected=-signal.SIGSEGV)
    # Reverse cross-compiler boundary is explicitly oracle-only.
    reverse = OUT / ('forth-calling-host' + opt)
    caller = OUT / ('forth-caller' + opt + '.o')
    run(CC + ['-DMAPPING_HOST', '-DMAPPING_INTEROP', '-c', fixture, '-o', caller])
    run([host, opt] + flags + [caller, source_obj, bridge, '-o', reverse])
    assert run([reverse, sparse]) == wanted
    for source_name, input_object in (('forth', fault_obj), ('host', None)):
        binary = OUT / (source_name + '-faults' + opt)
        extra = [input_object] if input_object else rename + ['-D__seed_syscall6=mapping_fake', runtime]
        run([host, opt] + flags + ['-I' + str(include), faults] + extra + ['-o', binary])
        assert run([binary]) == b'mapping fault contracts passed\n'
# Verify local Linux UAPI values independently from the runtime headers.
uapi = OUT / 'uapi.c'
uapi.write_text('''#include <linux/mman.h>
#include <asm/unistd.h>
#include <sys/types.h>
#include <limits.h>
#include <stdio.h>
int main(void) {
 printf("%d %d %d %d %d %d %d %lu %lu %lu %ld\\n", PROT_NONE, PROT_READ,
 PROT_WRITE, MAP_PRIVATE, MAP_ANONYMOUS, __NR_mmap, __NR_munmap,
 (unsigned long)sizeof(size_t), (unsigned long)sizeof(ssize_t),
 (unsigned long)sizeof(off_t), (long)SSIZE_MAX);
 return 0;
}
''')
uapi_exe = OUT / 'uapi'
run([host] + flags + [uapi, '-o', uapi_exe])
assert run([uapi_exe]) == b'0 1 2 2 32 9 11 8 8 8 9223372036854775807\n'
original = {'status': 'not run; requires pinned source and unchanged configuration'}
if args.gcc_source:
    gcc = args.gcc_source.resolve()
    config = args.gcc_config.resolve()
    source = gcc / 'gcc/config/host-linux.c'
    assert sha(source) == 'ca31293e9e9ebbdcb103008387dfc95e719f5f0abd25203901606d0ef6b7f4db'
    config_files = {p.name: sha(p) for p in sorted(config.glob('*.h'))}
    output = OUT / 'original-host-linux.o'
    run(CC + ['-c', '-DIN_GCC', '-DHAVE_CONFIG_H', '-I.', '-I' + str(gcc / 'gcc'),
              '-I' + str(gcc / 'include'), '-I' + str(gcc / 'libcpp/include'),
              source, '-o', output], cwd=config)
    assert config_files == {p.name: sha(p) for p in sorted(config.glob('*.h'))}
    assert sha(source) == 'ca31293e9e9ebbdcb103008387dfc95e719f5f0abd25203901606d0ef6b7f4db'
    original = {'status': 'passed complete untouched host-linux.c compile',
                'upstream_commit': '944765863eec87a9f37e297994fd2af960397138',
                'source_sha256': sha(source), 'config_directory': str(config),
                'configuration_header_sha256': config_files,
                'object_bytes': output.stat().st_size, 'object_sha256': sha(output),
                'limits': 'No new configure probe claims, no linked host-hooks or complete cc1 claim'}
assert identity == run(CC + ['--print-source-hash']).decode().strip()
assert all(sha(ROOT / name) == value for name, value in preserved.items())
files = ['runtime/gcc-seed/mapping.c', 'runtime/gcc-seed/include/sys/mman.h',
         'runtime/gcc-seed/include/limits.h', 'runtime/gcc-seed/include/sys/types.h',
         'tests/gcc/mapping-check.py', 'tests/gcc/mapping-check.c',
         'tests/gcc/mapping-faults.c', 'tests/gcc/mapping-host.c']
report = {
    'compiler_runtime_identity': identity, 'production': 'Forth compiled and linked, no host artifact input',
    'passed': ['anonymous and file private maps', 'PROT_NONE, READ, WRITE and READ|WRITE',
               'page-rounded lengths and partial unmap', 'non-destructive overlapping/unaligned hints',
               'zero length, huge length, bad descriptor, write-only file, misaligned offset/address',
               'sparse file offset above 4 GiB with private COW bytes and retained file identity',
               'actual SIGSEGV for none/read-only/unmapped access',
               'independent libc O0/O2, source O0/O2, host calling Forth O0/O2, Forth calling host O0/O2',
               'every raw kernel errno -4095..-1; outside interval pointer preservation',
               'exact syscall arguments, high pointer/size_t/off_t bits, errno preservation',
               'all unsupported flag/protection bits reject without a syscall', 'local Linux UAPI/LP64 check'],
    'memory_limit_bytes': LIMIT, 'serial': True, 'sparse_file_length': sparse.stat().st_size,
    'sparse_file_allocated_bytes': sparse.stat().st_blocks * 512,
    'original_gcc': original, 'preserved_sha256': preserved,
    'source_sha256': {name: sha(ROOT / name) for name in files},
    'local_uapi_sha256': {str(p): sha(p) for p in
        [Path('/usr/include/linux/mman.h'), Path('/usr/include/asm-generic/mman-common.h'), Path('/usr/include/x86_64-linux-gnu/asm/unistd_64.h')]},
    'artifact_sha256': {p.name: sha(p) for p in OUT.iterdir() if p.is_file() and p != sparse},
}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS mapping: Forth production, libc/source/bidirectional ABI O0/O2, complete errno interval, sparse >4 GiB')
print(OUT / 'report.json')
