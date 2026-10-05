#!/usr/bin/env python3
"""Serial byte-string span gate: Forth production and separate libc/ABI oracles."""
from pathlib import Path
import hashlib
import json
import os
import random
import resource
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='strcspn-', dir=ROOT / 'build-out'))
CC = [sys.executable, ROOT / 'tools/gcc-direct-cc.py']
LIMIT = 1024 ** 3
resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))
commands = []
cases = []


def add(text, reject):
    # Independent set-membership oracle; NUL ends both byte strings.
    string = text.split(b'\0', 1)[0]
    excluded = set(reject.split(b'\0', 1)[0])
    answer = next((i for i, byte in enumerate(string) if byte in excluded), len(string))
    cases.append((text + b'\0', reject + b'\0', answer))


# All byte pairs, including NUL and every signed-plain-char high byte.
# The bytes beyond the embedded terminator must never participate.
for a in range(256):
    for b in range(256):
        add(bytes((a, 0, 255)), bytes((b, 0, 128)))
for text, reject in ((b'', b''), (b'abc', b''), (b'', b'abc'),
                     (b'abc', b'x'), (b'abc', b'a'), (b'abc', b'b'),
                     (b'abc', b'c'), (b'abc', b'cba'), (b'abc', b'cccbbb'),
                     (b'NAME(arg) body\n', b'( \n'), (b'NAME body\n', b'( \n'),
                     (b'NAME\n', b'( \n'), (b'NAME', b'( \n')):
    add(text, reject)
all_bytes = bytes(range(1, 256))
for byte in range(1, 256):
    add(all_bytes, bytes((byte,)))
    add(all_bytes[::-1], bytes((byte, byte, byte)))
    add(bytes((byte,)) * 33, all_bytes)
for length in (0, 1, 2, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128,
               255, 256, 511, 512, 1023, 1024, 2047, 2048, 4094, 4095,
               4096, 65535, 65536, 262144):
    for reject in (b'', b'b', b'\xff', b'b' * (4095 if length <= 4096 else 3)):
        add(b'a' * length, reject)
    if length:
        for position in sorted({0, length // 2, length - 1}):
            add(b'a' * position + b'\xff' + b'a' * (length - position - 1), b'\xffb\xff')
# Long reject sets, repeated bytes, reversed order, and late matches.
for length in (1, 255, 4095, 4096, 16384):
    add(b'abc', b'x' * length)
    add(b'abc', b'x' * (length - 1) + b'b')
    add(b'abc', b'b' + b'x' * (length - 1))
rng = random.Random(0x57C5C0)
for unused in range(1000):
    length = rng.choice((0, 1, 2, 31, 255, 1023, 4095, 8192))
    reject_length = rng.choice((0, 1, 2, 16, 255, 1023, 4095))
    text = bytes(rng.randrange(1, 256) for i in range(length))
    reject = bytes(rng.randrange(1, 256) for i in range(reject_length))
    add(text, reject)
    if unused < 50:
        add(text, reject[::-1])
        add(text, reject + reject)
        if text:
            position = rng.randrange(len(text))
            add(text[:position] + b'\0' + text[position:], reject)
        if reject:
            position = rng.randrange(len(reject))
            add(text, reject[:position] + b'\0' + reject[position:])


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cap():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(arguments):
    command = list(map(str, arguments))
    result = subprocess.run(command, capture_output=True, timeout=300,
                            preexec_fn=cap, env=dict(os.environ, LC_ALL='C'))
    index = len(commands)
    (OUT / ('command-%02d.stdout' % index)).write_bytes(result.stdout)
    (OUT / ('command-%02d.stderr' % index)).write_bytes(result.stderr)
    commands.append({'arguments': command, 'returncode': result.returncode,
                     'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
                     'stderr': result.stderr.decode(errors='replace')})
    (OUT / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    assert result.returncode == 0 and not result.stderr, (command, result.returncode, result.stderr[-2000:])
    return result.stdout


preserved = {str(p.relative_to(ROOT)): sha(p) for p in
             [ROOT / 'seed-forth', ROOT / '000-seed.hex0', ROOT / 'runtime/gcc-seed/string.c']
             + sorted(ROOT.glob('*.fth'))}
assert (ROOT / 'seed-forth').stat().st_size == 1772
identity = run(CC + ['--print-source-hash']).decode().strip()
vector_file = OUT / 'vectors.bin'
with vector_file.open('wb') as stream:
    stream.write(struct.pack('<I', len(cases)))
    for text, reject, expected in cases:
        stream.write(struct.pack('<III', len(text), len(reject), expected))
        stream.write(text)
        stream.write(reject)
wanted = ''.join('%d %d\n' % (i, answer) for i, (_, _, answer) in enumerate(cases)).encode()
(OUT / 'expected.txt').write_bytes(wanted)
fixture = ROOT / 'tests/gcc/strcspn-check.c'
runtime = ROOT / 'runtime/gcc-seed/strcspn.c'
production = OUT / 'forth-production'
run(CC + [fixture, '-o', production])
assert run([production, vector_file]) == wanted
# The production binary is Forth-linked with no host dynamic loader/libc.
elf = production.read_bytes()
assert elf[:5] == b'\x7fELF\x02'
phoff = int.from_bytes(elf[32:40], 'little')
phsize = int.from_bytes(elf[54:56], 'little')
phcount = int.from_bytes(elf[56:58], 'little')
for index in range(phcount):
    offset = phoff + index * phsize
    assert int.from_bytes(elf[offset:offset + 4], 'little') not in (2, 3)
target = OUT / 'forth-strcspn.o'
run(CC + ['-Dstrcspn=seed_strcspn', '-c', runtime, '-o', target])
host = shutil.which('gcc')
assert host, 'host GCC is required for this separate O0/O2 oracle gate'
flags = ['-std=c90', '-pedantic', '-Wall', '-Wextra', '-Werror', '-fno-builtin',
         '-D_GNU_SOURCE', '-DSTRCSPN_HOST', '-no-pie', '-Wl,-z,noexecstack']
for opt in ('-O0', '-O2'):
    for mode, extra in (
        ('libc', []),
        ('forth-object', ['-DSTRCSPN_INTEROP', target]),
        ('host-source', ['-DSTRCSPN_INTEROP', '-Dstrcspn=seed_strcspn', runtime]),
    ):
        binary = OUT / (mode + opt)
        run([host, opt] + flags + [fixture] + extra + ['-o', binary])
        assert run([binary, vector_file]) == wanted, (mode, opt)
# Compile the public header and implementation together under strict host
# diagnostics, including incompatible-pointer/return-type diagnostics.
run([host, '-O2', '-std=c90', '-pedantic', '-Wall', '-Wextra', '-Werror',
     '-fno-builtin', '-I' + str(ROOT / 'runtime/gcc-seed/include'),
     '-c', runtime, '-o', OUT / 'header-typecheck.o'])
assert identity == run(CC + ['--print-source-hash']).decode().strip()
assert all(sha(ROOT / name) == value for name, value in preserved.items())
guarded = sum(len(text.split(b'\0', 1)[0]) < 4096 and len(reject.split(b'\0', 1)[0]) < 4096
              for text, reject, unused in cases)
report = {
    'compiler_runtime_source_identity': identity, 'seed_bytes': 1772,
    'production': 'Forth compiler, linker and runtime only; no host-built production objects',
    'cases': len(cases), 'all_byte_pair_cases': 65536,
    'guarded_cases': guarded, 'guard_edge_combinations_per_case': 4,
    'guarded_calls_per_executable': guarded * 4,
    'maximum_input_bytes_before_appended_nul': max(len(text) - 1 for text, _, _ in cases),
    'maximum_reject_bytes_before_appended_nul': max(len(reject) - 1 for _, reject, _ in cases),
    'python_oracle': 'independent unsigned byte-set membership, truncated at first NUL',
    'passed': {'forth_production': True, 'host_libc_O0_O2': True,
               'host_source_O0_O2': True, 'host_calling_forth_object_O0_O2': True,
               'size_t_header_typecheck': True, 'input_bytes_and_errno_preserved': True,
               'aliased_arguments': True},
    'size_t_abi': 'LP64 eight-byte unsigned result, exact size_t function pointer and prototype; lengths above 2^32 not allocated',
    'execution': 'serial', 'memory_limit_bytes': LIMIT,
    'preserved_sha256': preserved,
    'source_sha256': {str(p.relative_to(ROOT)): sha(p) for p in
                     [runtime, ROOT / 'runtime/gcc-seed/include/string.h', fixture, Path(__file__)]},
    'artifact_sha256': {p.name: sha(p) for p in OUT.iterdir() if p.is_file()},
}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS strcspn:', len(cases), 'vectors; Forth production, libc/host-source/Forth-object O0/O2; four guard edges')
print(OUT / 'report.json')
