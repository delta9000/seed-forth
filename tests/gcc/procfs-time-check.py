#!/usr/bin/env python3
"""Serial <=1 GiB gate for <features.h>, <sys/time.h> gettimeofday and <sys/procfs.h>.

Forth production versus host GCC/glibc facts, Forth raw-syscall faults, standalone
headers, bfd's own configure probes, and the unchanged binutils consumers."""
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
import time

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binutils-source-root', type=Path,
                    default=ROOT / 'build-out/stage-b-inputs/binutils-source')
options = parser.parse_args()
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='procfs-time-check-', dir=ROOT / 'build-out'))
CC = [sys.executable, str(ROOT / 'tools/gcc-direct-cc.py')]
INCLUDE = ROOT / 'runtime/gcc-seed/include'
TESTS = ROOT / 'tests/gcc'
LIMIT = 1024 ** 3
HEADERS = ['features.h', 'sys/time.h', 'sys/procfs.h']


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def attempt(args):
    command = [str(value) for value in args]
    return subprocess.run(command, capture_output=True, timeout=300, preexec_fn=limits,
                          env=dict(os.environ, LC_ALL='C'))


def run(args):
    result = attempt(args)
    assert result.returncode == 0 and not result.stderr, (
        [str(a) for a in args], result.returncode, result.stdout[-2000:], result.stderr[-2000:])
    return result.stdout


identity = run(CC + ['--print-source-hash']).decode().strip()
host = shutil.which('gcc')
assert host, 'GCC is required for the independent host glibc oracle'
HOST = [host, '-std=gnu99', '-U_FORTIFY_SOURCE', '-Wall', '-Wextra', '-Werror']
report = {'compiler_source_identity': identity,
          'production_toolchain': 'unchanged 1772-byte seed; Forth preprocessing, compilation and linking',
          'memory_limit_bytes': LIMIT, 'parallel_jobs': 1, 'host_oracles': []}

# 1. Layout facts: every procfs/time type and member, byte for byte with glibc.
layout = TESTS / 'procfs-layout.c'
run(CC + ['-o', OUT / 'layout', layout])
facts = run([OUT / 'layout'])
(OUT / 'layout.txt').write_bytes(facts)
for line in (b'prstatus_t size=336', b'prpsinfo_t size=136', b'prstatus_t.pr_reg offset=112',
             b'ELF_NGREG value=27', b'struct elf_siginfo size=12'):
    assert line in facts.splitlines(), line
# The runtime headers alone, under host GCC: pointer initializers fail under
# -Werror unless each typedef and member has exactly the expected C type.
run(HOST + ['-fno-builtin', '-nostdinc', '-I', INCLUDE, '-c', layout,
            '-o', OUT / 'host-runtime-headers.o'])
report['host_runtime_header_type_identity'] = True

# 2. gettimeofday: deterministic facts, cross-process clock windows, faults.
clock = TESTS / 'timeofday-check.c'
run(CC + ['-o', OUT / 'timeofday', clock])
clock_facts = run([OUT / 'timeofday', 'facts'])
(OUT / 'timeofday.txt').write_bytes(clock_facts)
assert b'null-zone result=0 errno=1234\n' in clock_facts, clock_facts
assert b'bad-time result=-1 errno=14\n' in clock_facts, clock_facts
assert b'bad-zone result=-1 errno=14\n' in clock_facts, clock_facts
for level in ['-O0', '-O2']:
    name = 'host-glibc-' + level[1:]
    run(HOST + [level, layout, '-o', OUT / (name + '-layout')])
    expected = run([OUT / (name + '-layout')])
    assert expected == facts, 'layout facts differ from host glibc at ' + level
    run(HOST + [level, '-DTIMEOFDAY_HOST_ORACLE', clock, '-o', OUT / (name + '-timeofday')])
    expected = run([OUT / (name + '-timeofday'), 'facts'])
    assert expected == clock_facts, 'gettimeofday facts differ from host glibc at ' + level
    report['host_oracles'].append({'optimization': level, 'identical_layout': True,
                                   'identical_timeofday_facts': True})


def reading(binary):
    seconds, micros = run([binary, 'now']).split()
    return int(seconds) * 1000000 + int(micros)


# Alternate Forth and host readings: each must fall between its neighbours,
# and the Forth readings must agree with Python's wall clock.
oracle = OUT / 'host-glibc-O2-timeofday'
windows = []
for unused in range(5):
    start = time.time_ns() // 1000
    first = reading(OUT / 'timeofday')
    middle = reading(oracle)
    last = reading(OUT / 'timeofday')
    finish = time.time_ns() // 1000
    assert start <= first <= middle <= last <= finish, (start, first, middle, last, finish)
    windows.append(finish - start)
report['clock_windows_microseconds'] = windows

runtime = ROOT / 'runtime/gcc-seed/timeofday.c'
renames = ['-Dgettimeofday=tested_gettimeofday', '-D__seed_syscall6=tested_timeofday_syscall']
run(CC + renames + ['-c', '-o', OUT / 'tested-timeofday.o', runtime])
run(CC + ['-o', OUT / 'faults', TESTS / 'timeofday-faults.c', OUT / 'tested-timeofday.o'])
assert run([OUT / 'faults']) == b'timeofday fault contracts passed\n'
report['scripted_faults'] = ['syscall 96 with both pointers forwarded unchanged and zero tail',
                             'every -4095..-1 result: -1 with that errno',
                             'other results: 0 with errno preserved']

# 3. Each header compiles standalone, twice, under Forth and strict host GCC.
for header in HEADERS:
    probe = OUT / ('standalone-' + header.replace('/', '-') + '.c')
    probe.write_text(f'#include <{header}>\n#include <{header}>\nint main(void) {{ return 0; }}\n')
    run(CC + ['-c', '-o', probe.with_suffix('.o'), probe])
    run([host, '-std=c99', '-pedantic', '-Wall', '-Wextra', '-Werror', '-fno-builtin',
         '-nostdinc', '-I', INCLUDE, '-c', probe, '-o', probe.with_suffix('.host.o')])
report['standalone_headers'] = HEADERS

# 4. bfd/configure.ac's own sys/procfs.h probes (bfd.m4 bodies) must answer
#    exactly as they do against host glibc.
PROLOGUE = '#define _SYSCALL32\n#define _STRUCTURED_PROC 1\n#include <sys/procfs.h>\n'
TYPES = ['prstatus_t', 'prstatus32_t', 'pstatus_t', 'pxstatus_t', 'pstatus32_t', 'prpsinfo_t',
         'prpsinfo32_t', 'psinfo_t', 'psinfo32_t', 'lwpstatus_t', 'lwpxstatus_t',
         'win32_pstatus_t']
MEMBERS = [('prstatus_t', 'pr_who'), ('prstatus32_t', 'pr_who'), ('prpsinfo_t', 'pr_pid'),
           ('prpsinfo32_t', 'pr_pid'), ('psinfo_t', 'pr_pid'), ('psinfo32_t', 'pr_pid'),
           ('lwpstatus_t', 'pr_context'), ('lwpstatus_t', 'pr_reg'), ('lwpstatus_t', 'pr_fpreg')]
probes = {'sys/procfs.h': '#include <stdio.h>\n#include <sys/types.h>\n#include <sys/stat.h>\n'
                          '#include <stdlib.h>\n#include <stddef.h>\n#include <string.h>\n'
                          '#include <inttypes.h>\n#include <stdint.h>\n#include <unistd.h>\n'
                          '#include <sys/procfs.h>\nint main () { ; return 0; }\n'}
for name in TYPES:
    probes[name] = PROLOGUE + f'int\nmain ()\n{{\n{name} avar\n  ;\n  return 0;\n}}\n'
for name, member in MEMBERS:
    probes[name + '.' + member] = PROLOGUE + (
        f'int\nmain ()\n{{\n{name} avar; void* aref = (void*) &avar.{member}\n'
        '  ;\n  return 0;\n}\n')
answers = {}
for key, text in probes.items():
    probe = OUT / ('configure-' + key.replace('/', '-').replace('.', '-') + '.c')
    probe.write_text(text)
    forth = attempt(CC + ['-c', '-o', probe.with_suffix('.o'), probe]).returncode == 0
    glibc = attempt([host, '-c', '-o', probe.with_suffix('.host.o'), probe]).returncode == 0
    assert forth == glibc, (key, forth, glibc)
    answers[key] = forth
FOUND = {'sys/procfs.h', 'prstatus_t', 'prpsinfo_t', 'prpsinfo_t.pr_pid'}
assert {key for key, found in answers.items() if found} == FOUND, answers
report['bfd_configure_probe_answers'] = answers

# 5. Unchanged binutils consumers.
binutils = options.binutils_source_root.resolve()
if (binutils / 'bfd/hosts/x86-64linux.h').is_file():
    core = TESTS / 'procfs-core-header.c'
    search = ['-I', binutils / 'include', '-I', binutils / 'bfd']
    run(CC + search + ['-o', OUT / 'core-header', core])
    core_facts = run([OUT / 'core-header'])
    (OUT / 'core-header.txt').write_bytes(core_facts)
    run(HOST + search + ['-o', OUT / 'host-glibc-core-header', core])
    assert run([OUT / 'host-glibc-core-header']) == core_facts, 'core header layouts differ'
    # elf64-x86-64.c recognizes notes by these exact descriptor sizes.
    for line in (b'prstatus64_t size=336', b'prstatusx32_t size=296', b'prpsinfo64_t size=136',
                 b'prpsinfo32_t size=124'):
        assert line in core_facts.splitlines(), line
    configuration = OUT / 'libiberty-config'
    configuration.mkdir()
    (configuration / 'config.h').write_text(
        '/* Minimal hand-written stand-in; not a configure result. */\n'
        '#define HAVE_STDLIB_H 1\n#define HAVE_STRING_H 1\n#define HAVE_UNISTD_H 1\n'
        '#define HAVE_SYS_TYPES_H 1\n#define HAVE_SYS_TIME_H 1\n#define HAVE_TIME_H 1\n'
        '#define HAVE_GETTIMEOFDAY 1\n')
    consumers = {}
    for source in ['libiberty/mkstemps.c', 'libiberty/gettimeofday.c']:
        path = binutils / source
        command = CC + ['-I', configuration, '-I', binutils / 'include', '-c', path,
                        '-o', OUT / ('original-' + path.stem + '.o')]
        run(command)
        consumers[source] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                             'command': list(map(str, command))}
    consumers['bfd/hosts/x86-64linux.h'] = {
        'sha256': hashlib.sha256((binutils / 'bfd/hosts/x86-64linux.h').read_bytes()).hexdigest(),
        'scope': 'layouts identical to host GCC/glibc; elf64-x86-64.c note sizes'}
    report['original_source_contract'] = {
        'consumers': consumers,
        'scope': 'unchanged sources compile; mkstemps uses gettimeofday, libiberty\'s '
                 'replacement keeps a compatible prototype; no link claim'}
else:
    print('SKIP: original binutils consumers require the pinned binutils source')
assert identity == run(CC + ['--print-source-hash']).decode().strip(), 'compiler changed'
names = ['runtime/gcc-seed/include/features.h', 'runtime/gcc-seed/include/sys/time.h',
         'runtime/gcc-seed/include/sys/procfs.h', 'runtime/gcc-seed/timeofday.c',
         'tests/gcc/procfs-layout.c', 'tests/gcc/procfs-core-header.c',
         'tests/gcc/timeofday-check.c', 'tests/gcc/timeofday-faults.c',
         'tests/gcc/procfs-time-check.py']
report['source_sha256'] = {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in names}
report['artifact_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in OUT.iterdir() if p.is_file()}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS: procfs/time layouts and gettimeofday match host glibc O0/O2; faults; '
      'standalone headers; bfd configure probes; original consumers')
print(OUT / 'report.json')
