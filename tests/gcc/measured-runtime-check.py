#!/usr/bin/env python3
"""Serial four-interface gate: Forth production, separate host and ABI oracles."""
from pathlib import Path
import hashlib
import json
import os
import random
import resource
import shutil
import struct
import sys
import tempfile
from measured_runtime_runner import Runner

ROOT = Path(__file__).resolve().parents[2]
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='measured-runtime-', dir=ROOT / 'build-out'))
TMP = OUT / 'tmp'
TMP.mkdir()
LIMIT = 1024 ** 3
resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
CC = [sys.executable, ROOT / 'tools/gcc-direct-cc.py']
runner = Runner(OUT, ROOT, TMP, LIMIT)
commands = runner.commands
run = runner.run


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


preserved = {str(p.relative_to(ROOT)): sha(p) for p in
             [ROOT / 'seed-forth', ROOT / '000-seed.hex0'] + sorted(ROOT.glob('*.fth'))}
assert (ROOT / 'seed-forth').stat().st_size == 1772
assert preserved['seed-forth'] == '697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e'
identity = run(CC + ['--print-source-hash']).decode().strip()
cases = []


def add(text, accept):
    source = text.split(b'\0', 1)[0]
    accepted = set(accept.split(b'\0', 1)[0])
    span = next((i for i, byte in enumerate(source) if byte not in accepted), len(source))
    first = next((i for i, byte in enumerate(source) if byte in accepted), -1)
    cases.append((text + b'\0', accept + b'\0', span, first))


for a in range(256):
    for b in range(256):
        add(bytes((a, 0, 255)), bytes((b, 0, 128)))
for text, accept in ((b'', b''), (b'', b'abc'), (b'abc', b''), (b'abc', b'cba'),
                     (b'abc', b'aaabbb'), (b'abc', b'c'), (b'abc', b'x'),
                     (b'eEV', b'eEV'), (b'iuue', b'eEV')):
    add(text, accept)
all_bytes = bytes(range(1, 256))
for byte in range(1, 256):
    add(all_bytes, bytes((byte,)))
    add(all_bytes[::-1], bytes((byte, byte, byte)))
    add(bytes((byte,)) * 33, all_bytes)
for length in (0, 1, 2, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128,
               255, 256, 511, 512, 1023, 1024, 2047, 2048, 4094, 4095,
               4096, 65535, 65536, 262144):
    for accept in (b'', b'a', b'b', b'\xff', b'b' * (4095 if length <= 4096 else 3)):
        add(b'a' * length, accept)
    if length:
        for position in sorted({0, length // 2, length - 1}):
            text = b'a' * position + b'\xff' + b'a' * (length - position - 1)
            add(text, b'\xffb\xff')
            add(text, b'aa')
for length in (1, 255, 4095, 4096, 16384):
    add(b'abc', b'x' * length)
    add(b'abc', b'x' * (length - 1) + b'b')
    add(b'aaa', b'x' * (length - 1) + b'a')
rng = random.Random(0xA11CE)
for i in range(1000):
    text = bytes(rng.randrange(1, 256) for _ in range(rng.choice((0, 1, 31, 255, 1023, 4095, 8192))))
    accept = bytes(rng.randrange(1, 256) for _ in range(rng.choice((0, 1, 2, 16, 255, 1023))))
    add(text, accept)
    if i < 100:
        add(text, accept[::-1])
        add(text, accept + accept)
        add(text[:len(text)//2] + b'\0' + text[len(text)//2:], accept)
        add(text, accept[:len(accept)//2] + b'\0' + accept[len(accept)//2:])
vectors = OUT / 'vectors.bin'
with vectors.open('wb') as stream:
    stream.write(struct.pack('<I', len(cases)))
    for text, accept, span, first in cases:
        stream.write(struct.pack('<IIII', len(text), len(accept), span, first + 1))
        stream.write(text)
        stream.write(accept)
wanted = ''.join('%d %d %d\n' % (i, span, first) for i, (_, _, span, first) in enumerate(cases)).encode()
(OUT / 'expected-spans.txt').write_bytes(wanted)
files = OUT / 'files'
files.mkdir()
for mode in (0o000, 0o100, 0o200, 0o400, 0o600, 0o700, 0o755):
    path = files / ('mode-%03o' % mode)
    path.write_bytes(b'unchanged\x00\xff file contents\n')
    path.chmod(mode)
(files / 'directory').mkdir()
(files / 'link').symlink_to('mode-700')
(files / 'dangling').symlink_to('missing')
(files / 'loop').symlink_to('loop')
paths = [*sorted(files.glob('mode-*')), files / 'directory', files / 'link',
         files / 'dangling', files / 'loop', files / 'missing', files / 'mode-700/child']
file_before = {p.name: (p.stat().st_mode, sha(p)) for p in sorted(files.glob('mode-*')) if os.access(p, os.R_OK)}
# Some fixture modes are unreadable to a non-root user; compare their content
# afterwards after temporarily restoring owner read permission, never targets outside OUT.
include = ROOT / 'runtime/gcc-seed/include'
fixture = ROOT / 'tests/gcc/access-pid-check.c'
strings = ROOT / 'tests/gcc/positive-spans-check.c'
faults = ROOT / 'tests/gcc/access-pid-faults.c'
bridge = ROOT / 'tests/gcc/measured-runtime-host.c'
runtimes = [ROOT / 'runtime/gcc-seed' / (name + '.c') for name in ('access', 'getpid', 'strpbrk', 'strspn')]
renames = ['-D' + p.stem + '=tested_' + p.stem for p in runtimes]
productions = []
for source, arguments, expected in ((strings, [vectors], wanted), (fixture, paths, None)):
    binary = OUT / ('forth-' + source.stem)
    run(CC + [source, '-o', binary])
    output = run([binary] + arguments)
    if expected is not None:
        assert output == expected
    else:
        permission_output = output
    elf = binary.read_bytes()
    assert elf[:5] == b'\x7fELF\x02'
    phoff, phsize, phcount = struct.unpack_from('<Q', elf, 32)[0], struct.unpack_from('<H', elf, 54)[0], struct.unpack_from('<H', elf, 56)[0]
    assert all(struct.unpack_from('<I', elf, phoff + i * phsize)[0] not in (2, 3) for i in range(phcount))
    productions.append(binary.name)
objects = []
fault_objects = []
for source in runtimes:
    target = OUT / ('forth-' + source.stem + '.o')
    run(CC + renames + ['-c', source, '-o', target])
    objects.append(target)
    if source.stem in ('access', 'getpid'):
        target = OUT / ('fault-' + source.stem + '.o')
        run(CC + renames + ['-D__seed_syscall6=measured_fake', '-c', source, '-o', target])
        fault_objects.append(target)
fault_exe = OUT / 'forth-faults'
run(CC + [faults] + fault_objects + ['-o', fault_exe])
assert run([fault_exe]) == b'access/getpid injected contracts passed\n'
host = shutil.which('gcc')
assert host, 'independent host GCC required by the oracle gate'
flags = ['-std=c90', '-pedantic', '-Wall', '-Wextra', '-Werror', '-fno-builtin',
         '-D_GNU_SOURCE', '-no-pie', '-Wl,-z,noexecstack']
for opt in ('-O0', '-O2'):
    host_objects = []
    for source in runtimes:
        target = OUT / ('host-' + source.stem + opt + '.o')
        run([host, opt] + flags + ['-fno-pie', '-I' + str(include)] + renames + ['-c', source, '-o', target])
        host_objects.append(target)
    for mode, extras in (('libc', []), ('forth-object', objects), ('host-source', host_objects)):
        binary = OUT / (mode + '-strings' + opt)
        defines = ['-DSPANS_HOST'] + (['-DSPANS_INTEROP'] if extras else [])
        run([host, opt] + flags + defines + [strings, bridge] + extras + ['-o', binary])
        assert run([binary, vectors]) == wanted, (mode, opt)
        binary = OUT / (mode + '-access' + opt)
        run([host, opt] + flags + (['-DMEASURED_INTEROP'] if extras else []) + [fixture, bridge] + extras + ['-o', binary])
        assert run([binary] + paths) == permission_output, (mode, opt)
    # Forth callers cross into host-source callees: oracle-only executables.
    for source, defines, arguments, expected in (
        (strings, ['-DSPANS_HOST', '-DSPANS_INTEROP'], [vectors], wanted),
        (fixture, ['-DMEASURED_INTEROP'], paths, permission_output),
    ):
        caller = OUT / (source.stem + '-caller' + opt + '.o')
        run(CC + defines + ['-c', source, '-o', caller])
        binary = OUT / (source.stem + '-reverse' + opt)
        run([host, opt] + flags + [caller, bridge] + host_objects + ['-o', binary])
        assert run([binary] + arguments) == expected
    for provider in ('forth', 'host'):
        binary = OUT / (provider + '-faults' + opt)
        extra = fault_objects if provider == 'forth' else renames + ['-D__seed_syscall6=measured_fake'] + runtimes[:2]
        run([host, opt] + flags + ['-I' + str(include), faults] + extra + ['-o', binary])
        assert run([binary]) == b'access/getpid injected contracts passed\n'
# Local authoritative Linux AMD64 UAPI and host ABI, never production includes.
uapi = OUT / 'uapi.c'
uapi.write_text('''#include <asm/unistd.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
int main(void) {
 int (*a)(const char *, int) = access;
 pid_t (*p)(void) = getpid;
 size_t (*s)(const char *, const char *) = strspn;
 char *(*b)(const char *, const char *) = strpbrk;
 printf("%d %d %d %d %d %d %lu %d %lu %d\\n", __NR_access, __NR_getpid,
 F_OK, X_OK, W_OK, R_OK, (unsigned long)sizeof(pid_t), (pid_t)-1 < 0,
 (unsigned long)sizeof(size_t), a != 0 && p != 0 && s != 0 && b != 0);
 return 0;
}
''')
uapi_exe = OUT / 'uapi'
run([host] + flags + [uapi, '-o', uapi_exe])
assert run([uapi_exe]) == b'21 39 0 1 2 4 4 1 8 1\n'
assert identity == run(CC + ['--print-source-hash']).decode().strip()
assert all(sha(ROOT / name) == digest for name, digest in preserved.items())
for path in sorted(files.glob('mode-*')):
    mode = path.stat().st_mode
    if path.name in file_before:
        assert file_before[path.name] == (mode, sha(path))
    path.chmod(mode | 0o400)
    assert path.read_bytes() == b'unchanged\x00\xff file contents\n'
    path.chmod(mode)
report = {
    'compiler_runtime_identity': identity,
    'production': 'Forth compilation/linking/runtime only, no host-built artifact inputs',
    'production_executables': productions, 'seed_bytes': 1772,
    'passed': ['Forth production', 'independent libc and host-source O0/O2',
               'host calling Forth and Forth calling host O0/O2', 'all 65536 unsigned-byte/NUL pairs',
               'long/duplicate/overlapping strings and independent Python membership oracle',
               'both arguments at all four guard-page edge combinations', 'exact strpbrk pointer and size_t spans',
               'actual own files, all mode combinations, symlinks, missing/non-directory/loop paths',
               'read-only path page tails, bad pointers, empty/unterminated/overlong paths',
               'each invalid mode bit and full kernel errno band -4095..-1',
               'syscall argument widths, getpid non-caching and errno preservation', 'local Linux UAPI and exact public types'],
    'vector_cases': len(cases), 'maximum_string_bytes': max(len(x)-1 for x, _, _, _ in cases),
    'guarded_cases': sum(len(x.split(b'\0',1)[0]) < 4096 and len(y.split(b'\0',1)[0]) < 4096 for x,y,_,_ in cases),
    'local_uapi_sha256': {str(p): sha(p) for p in [Path('/usr/include/x86_64-linux-gnu/asm/unistd_64.h'), Path('/usr/include/unistd.h'), Path('/usr/include/x86_64-linux-gnu/bits/typesizes.h'), Path('/usr/include/asm-generic/posix_types.h')]},
    'memory_limit_bytes': LIMIT, 'serial': True, 'subprocess_timeout_seconds': 300,
    'scope_limits': 'No setbuf; no compiler/parser changes, fresh configure/cohort, complete cc1 link, bootstrap or broad gate claim. size_t above 2^32 is typechecked, not allocated. Linux access is a time-of-check observation, not authorization for a later open.',
    'preserved_sha256': preserved,
    'source_sha256': {str(p.relative_to(ROOT)): sha(p) for p in runtimes + [include/'unistd.h', include/'string.h', fixture, strings, faults, bridge, Path(__file__), ROOT/'tests/gcc/measured_runtime_runner.py']},
    'artifact_sha256': {p.name: sha(p) for p in OUT.iterdir() if p.is_file()},
}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS measured runtime:', len(cases), 'string vectors; access/getpid kernel/errno; Forth and O0/O2 bidirectional oracles')
print(OUT / 'report.json')
