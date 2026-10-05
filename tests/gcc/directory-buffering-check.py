#!/usr/bin/env python3
"""Serial bounded getcwd/setbuf gate with independent host and syscall oracles."""
from pathlib import Path
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
from measured_runtime_runner import Runner

ROOT = Path(__file__).resolve().parents[2]
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='directory-buffering-', dir=ROOT / 'build-out'))
TMP = OUT / 'tmp'
TMP.mkdir()
resource.setrlimit(resource.RLIMIT_AS, (1024 ** 3, 1024 ** 3))
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
CC = [sys.executable, ROOT / 'tools/gcc-direct-cc.py']
commands = []
supervisor = Runner(OUT, ROOT, TMP, 1024 ** 3)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(arguments, status=0, stderr=b'', cwd=None, cwd_fd=None, timeout=300, stderr_fd=None, file_limit=None):
    command = list(map(str, arguments))
    index = len(commands)
    timed_out = False
    def child_setup():
        if cwd_fd is not None:
            os.fchdir(cwd_fd)
        if file_limit is not None:
            resource.setrlimit(resource.RLIMIT_FSIZE, (file_limit, file_limit))
    with (OUT / ('command-%03d.stdout' % index)).open('wb') as out, \
         (OUT / ('command-%03d.stderr' % index)).open('wb') as err:
        process = subprocess.Popen(command, cwd=cwd or ROOT, stdout=out, stderr=err if stderr_fd is None else stderr_fd,
            env=dict(os.environ, LC_ALL='C', TMPDIR=str(TMP)), start_new_session=True,
            pass_fds=() if cwd_fd is None else (cwd_fd,),
            preexec_fn=child_setup if cwd_fd is not None or file_limit is not None else None)
        try:
            result = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            cleanup = supervisor.cleanup(process)
            result = process.returncode
    output = (OUT / ('command-%03d.stdout' % index)).read_bytes()
    errors = (OUT / ('command-%03d.stderr' % index)).read_bytes()
    commands.append({'arguments': command, 'cwd': str(cwd or ROOT),
        'cwd_fd': cwd_fd, 'file_limit': file_limit, 'returncode': result, 'timed_out': timed_out, 'cleanup': cleanup,
        'stdout_sha256': hashlib.sha256(output).hexdigest(),
        'stderr': errors.decode(errors='replace')})
    (OUT / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    assert cleanup['complete'] and cleanup['remaining'] == [], cleanup
    if timed_out:
        assert result == -signal.SIGKILL
        raise TimeoutError('owned process group killed and waited; record saved')
    assert result == status and errors == stderr, (command, result, errors[-2000:], output[-2000:])
    return output

# Real timeout branch, including child-group death and retained partial output.
try:
    run([sys.executable, '-c', 'import os,time; print("partial",flush=True); os.fork(); time.sleep(60)'], timeout=.2)
    raise AssertionError('timeout branch did not run')
except TimeoutError:
    assert commands[-1]['timed_out'] and (OUT / 'command-000.stdout').read_bytes() == b'partial\n'
    assert len(commands[-1]['cleanup']['reaped_descendants']) == 1

preserved = {str(p.relative_to(ROOT)): sha(p) for p in
    [ROOT / 'seed-forth', ROOT / '000-seed.hex0'] + sorted(ROOT.glob('*.fth'))}
assert (ROOT / 'seed-forth').stat().st_size == 1772
assert preserved['seed-forth'] == '697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e'
identity = run(CC + ['--print-source-hash']).decode().strip()
include = ROOT / 'runtime/gcc-seed/include'
fixture = ROOT / 'tests/gcc/getcwd-check.c'
getcwd = ROOT / 'runtime/gcc-seed/getcwd.c'
setbuf = ROOT / 'runtime/gcc-seed/setbuf.c'
bridge = ROOT / 'tests/gcc/measured-runtime-host.c'
host = shutil.which('gcc')
assert host
flags = ['-std=c90', '-pedantic', '-Wall', '-Wextra', '-Werror', '-fno-builtin',
    '-D_GNU_SOURCE', '-no-pie', '-Wl,-z,noexecstack']
normal = OUT / 'own directory'
normal.mkdir()
(normal / 'physical').mkdir()
(normal / 'alias').symlink_to('physical', target_is_directory=True)
cases = [('/', '/'), (normal, str(normal)), (normal / 'alias', str(normal / 'physical'))]
renamed = OUT / 'before-rename'
renamed.mkdir()
rename_fd = os.open(renamed, os.O_RDONLY | os.O_DIRECTORY)
renamed.rename(OUT / 'after-rename')
deleted = OUT / 'deleted'
deleted.mkdir()
deleted_fd = os.open(deleted, os.O_RDONLY | os.O_DIRECTORY)
deleted.rmdir()
long_root = OUT / 'long-root'
long_root.mkdir()
long_fds = [os.open(long_root, os.O_RDONLY | os.O_DIRECTORY)]
long_names = []
long_path = str(long_root)
while len(long_path) < 4300:
    name = ('part%02d-' % len(long_names)) + 'x' * 193
    os.mkdir(name, dir_fd=long_fds[-1])
    long_fds.append(os.open(name, os.O_RDONLY | os.O_DIRECTORY, dir_fd=long_fds[-1]))
    long_names.append(name)
    long_path += '/' + name

def exercise_cwd(binary, libc=False):
    for cwd, expected in cases:
        assert run([binary, 'normal', expected], cwd=cwd) == b'caller cwd contract passed\n'
    assert run([binary, 'normal', str(OUT / 'after-rename')], cwd_fd=rename_fd) == b'caller cwd contract passed\n'
    assert run([binary, 'deleted', '-'], cwd_fd=deleted_fd) == b'rejected cwd storage preserved\n'
    wanted = b'libc long-path fallback passed\n' if libc else b'rejected cwd storage preserved\n'
    assert run([binary, 'long', long_path], cwd_fd=long_fds[-1]) == wanted

production = OUT / 'forth-cwd'
run(CC + [fixture, '-o', production])
exercise_cwd(production)
stream = OUT / 'forth-setbuf'
run(CC + [ROOT / 'tests/gcc/setbuf-check.c', '-o', stream])
stream_file = OUT / 'stream.bin'
assert run([stream, 'normal', stream_file]) == b'unbuffered stream contract passed\n'
assert stream_file.read_bytes() == b'A\0B\xff'
message = b''
for mode in ('unsupported', 'bad-buffer', 'null-stream', 'closed-stream'):
    assert run([stream, mode, stream_file], status=127, stderr=message) == b''
    if mode in ('unsupported', 'bad-buffer'):
        assert stream_file.read_bytes() == b''
# Terminal rejection performs no stderr I/O and cannot generate SIGPIPE.
read_end, write_end = os.pipe()
os.close(read_end)
readonly = os.open(stream_file, os.O_RDONLY)
try:
    for fd in (write_end, readonly):
        for mode in ('unsupported', 'bad-buffer', 'null-stream', 'closed-stream'):
            assert run([stream, mode, stream_file], status=127, stderr_fd=fd) == b''
finally:
    os.close(write_end)
    os.close(readonly)
# No stderr write: file-size limits cannot generate SIGXFSZ here.
for mode in ('unsupported', 'bad-buffer', 'null-stream', 'closed-stream'):
    assert run([stream, mode, stream_file], status=127, file_limit=0) == b''
# The full blocking pipe regression proves termination does not wait on stderr.
read_end, write_end = os.pipe()
os.set_blocking(write_end, False)
filled = 0
while True:
    try:
        filled += os.write(write_end, b'x' * 4096)
    except BlockingIOError:
        break
os.set_blocking(write_end, True)
try:
    assert filled > 0
    for mode in ('unsupported', 'bad-buffer', 'null-stream', 'closed-stream'):
        assert run([stream, mode, stream_file], status=127, stderr_fd=write_end, timeout=3) == b''
finally:
    os.close(read_end)
    os.close(write_end)
for binary in (production, stream):
    data = binary.read_bytes()
    phoff = struct.unpack_from('<Q', data, 32)[0]
    phsize, phcount = struct.unpack_from('<HH', data, 54)
    assert all(struct.unpack_from('<I', data, phoff+i*phsize)[0] not in (2,3) for i in range(phcount))

forth_obj = OUT / 'forth-getcwd.o'
run(CC + ['-Dgetcwd=tested_getcwd', '-c', getcwd, '-o', forth_obj])
fault_obj = OUT / 'fault-getcwd.o'
run(CC + ['-Dgetcwd=tested_getcwd', '-D__seed_syscall6=directory_fake', '-c', getcwd, '-o', fault_obj])
fault = OUT / 'forth-faults'
run(CC + [ROOT / 'tests/gcc/getcwd-faults.c', fault_obj, '-o', fault])
assert run([fault]) == b'cwd injected contracts passed\n'
set_defines = ['-Dsetbuf=tested_setbuf', '-Dfileno=directory_fileno', '-D_exit=directory_exit']
set_obj = OUT / 'forth-setbuf.o'
run(CC + set_defines + ['-c', setbuf, '-o', set_obj])
abi_fixture = ROOT / 'tests/gcc/setbuf-abi.c'
for opt in ('-O0', '-O2'):
    host_obj = OUT / ('host-getcwd' + opt + '.o')
    run([host, opt] + flags + ['-fno-pie', '-I'+str(include), '-Dgetcwd=tested_getcwd', '-c', getcwd, '-o', host_obj])
    for mode, obj in (('libc', None), ('forth', forth_obj), ('source', host_obj)):
        binary = OUT / (mode + '-cwd' + opt)
        defines = ['-DDIRECTORY_INTEROP'] if obj else ['-DDIRECTORY_LIBC']
        run([host, opt] + flags + defines + [fixture, bridge] + ([obj] if obj else []) + ['-o', binary])
        exercise_cwd(binary, libc=obj is None)
        guarded = OUT / (mode + '-guards' + opt)
        run([host, opt] + flags + defines + [ROOT / 'tests/gcc/getcwd-guards.c', bridge] + ([obj] if obj else []) + ['-o', guarded])
        assert run([guarded, str(ROOT)]) == b'cwd guarded storage passed\n'
    caller = OUT / ('cwd-caller' + opt + '.o')
    run(CC + ['-DDIRECTORY_INTEROP', '-c', fixture, '-o', caller])
    reverse = OUT / ('cwd-reverse' + opt)
    run([host, opt] + flags + [caller, bridge, host_obj, '-o', reverse])
    exercise_cwd(reverse)
    for provider, extras in (('forth', [fault_obj]), ('host', ['-I'+str(include), '-Dgetcwd=tested_getcwd', '-D__seed_syscall6=directory_fake', getcwd])):
        binary = OUT / (provider + '-faults' + opt)
        run([host, opt] + flags + [ROOT / 'tests/gcc/getcwd-faults.c'] + extras + ['-o', binary])
        assert run([binary]) == b'cwd injected contracts passed\n'
    host_set = OUT / ('host-setbuf' + opt + '.o')
    run([host, opt] + flags + ['-fno-pie', '-I'+str(include)] + set_defines + ['-c', setbuf, '-o', host_set])
    for provider, obj in (('forth', set_obj), ('host', host_set)):
        binary = OUT / (provider + '-setbuf-abi' + opt)
        run([host, opt] + flags + [abi_fixture, obj, '-o', binary])
        assert run([binary]) == b'setbuf public-call ABI passed\n'
        assert run([binary, 'x'], status=127) == b''
        assert run([binary, 'i'], status=127) == b''
    set_caller = OUT / ('setbuf-caller' + opt + '.o')
    run(CC + ['-c', abi_fixture, '-o', set_caller])
    binary = OUT / ('setbuf-reverse' + opt)
    run([host, opt] + flags + [set_caller, host_set, '-o', binary])
    assert run([binary]) == b'setbuf public-call ABI passed\n'
    assert run([binary, 'x'], status=127) == b''
    assert run([binary, 'i'], status=127) == b''
    libc_set = OUT / ('libc-setbuf' + opt)
    run([host, opt] + flags + ['-DDIRECTORY_LIBC', ROOT / 'tests/gcc/setbuf-check.c', '-o', libc_set])
    assert run([libc_set, 'normal', stream_file]) == b'unbuffered stream contract passed\n'

uapi = OUT / 'uapi.c'
uapi.write_text('''#include <asm/unistd.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <linux/limits.h>
int main(void) {
 char *(*cwd)(char *, size_t) = getcwd;
 void (*buf)(FILE *, char *) = setbuf;
 printf("%d %lu %d %d %d %d %d %d\\n", __NR_getcwd, (unsigned long)sizeof(size_t),
 EINVAL, ERANGE, ENOENT, ENAMETOOLONG, PATH_MAX, cwd != 0 && buf != 0);
 return 0;
}
''')
uapi_exe = OUT / 'uapi'
run([host] + flags + [uapi, '-o', uapi_exe])
assert run([uapi_exe]) == b'79 8 22 34 2 36 4096 1\n'
for i in reversed(range(len(long_names))):
    os.close(long_fds[i+1])
    os.rmdir(long_names[i], dir_fd=long_fds[i])
os.close(long_fds[0])
long_root.rmdir()
os.close(rename_fd)
os.close(deleted_fd)
assert identity == run(CC + ['--print-source-hash']).decode().strip()
assert all(sha(ROOT / name) == digest for name, digest in preserved.items())
headers = [Path(p) for p in ('/usr/include/unistd.h', '/usr/include/stdio.h', '/usr/include/linux/limits.h',
    '/usr/include/x86_64-linux-gnu/asm/unistd_64.h', '/usr/include/asm-generic/errno-base.h', '/usr/include/asm-generic/errno.h')]
report = {'compiler_runtime_identity': identity, 'production': 'Forth only, static ELF, no host artifacts',
    'passed': ['real root/own/symlink/renamed/deleted working directories', 'all sizes through exact fit and larger',
    'caller pointer identity, NUL, storage guards, errno', 'NULL allocating forms explicitly rejected',
    'real greater-than-4096 path boundary with independent libc fallback contrast', 'read-only/no-access/bad-pointer kernel EFAULT',
    'all 4095 kernel errors and full-width syscall argument forwarding', 'synthetic non-absolute result rejected',
    'fopen/fdopen NULL setbuf immediate binary writes and reads', 'non-NULL immediate silent status 127 and no post-call writes',
    'actual full-blocking-pipe/closed-pipe/read-only/file-size-limited stderr',
    'public types and local UAPI constants', 'O0/O2 independent libc and host source', 'bidirectional getcwd/setbuf ABI',
    'timeout process-group cleanup branch with retained logs', 'unchanged seed and all Forth compiler layers'],
    'not_run': ['chroot/unreachable real cwd', 'credential/security changes', 'full component/broad suite', 'genuine configure replay', 'GCC link/execution/bootstrap'],
    'required_predecessor': 'qualified 80667 measured-runtime harness packet',
    'cleanup_helper_sha256': sha(ROOT / 'tests/gcc/measured_runtime_runner.py'),
    'host_headers': {str(p): sha(p) for p in headers}, 'preserved': preserved,
    'long_path_bytes_without_NUL': len(long_path), 'commands': len(commands)}
(OUT / 'result.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({'out': str(OUT), 'identity': identity, 'passed': True}))
