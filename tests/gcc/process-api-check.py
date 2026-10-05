#!/usr/bin/env python3
"""Serial <=1 GiB process-API gate: Forth production, host GCC/glibc oracles,
and original binutils 2.30 libiberty pex_* built by Forth and run for real."""
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
OUT = Path(tempfile.mkdtemp(prefix='process-api-check-', dir=ROOT / 'build-out'))
CC = [sys.executable, str(ROOT / 'tools/gcc-direct-cc.py')]
INCLUDE = ROOT / 'runtime/gcc-seed/include'
TESTS = ROOT / 'tests/gcc'
LIMIT = 1024 ** 3
commands = []
# The default execvp path and the pex pipeline need sh, printf and tr there.
ENVIRONMENT = dict(os.environ, LC_ALL='C', PATH='/usr/bin:/bin')
MISSING = b"pex-check: error trying to exec 'no-such-seed-program': execvp: No such file or directory\n"
# Hand-written libiberty configuration describing this runtime (glibc-like
# headers and process calls; no wait4/getrusage/gettimeofday/dup3/spawn).
CONFIG = '''/* Hand-written stand-in for libiberty configure; not a configure result. */
#define STDC_HEADERS 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_UNISTD_H 1
#define HAVE_FCNTL_H 1
#define HAVE_LIMITS_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_WAITPID 1
#define HAVE_FORK 1
#define HAVE_VFORK 1
#define HAVE_WORKING_FORK 1
#define HAVE_WORKING_VFORK 1
#define HAVE_GETCWD 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
'''
UNITS = ['pex-unix', 'pex-common', 'xmalloc', 'xstrerror', 'make-temp-file',
         'concat', 'xexit', 'xstrdup', 'mkstemps']


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(args, stderr=b''):
    command = [str(value) for value in args]
    result = subprocess.run(command, capture_output=True, timeout=300, preexec_fn=limits,
                            env=ENVIRONMENT, stdin=subprocess.DEVNULL)
    commands.append({'arguments': command, 'returncode': result.returncode,
                     'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
                     'stderr': result.stderr.decode(errors='replace')[-2000:]})
    assert result.returncode == 0 and result.stderr == stderr, (command, result.returncode,
                                                                result.stdout[-2000:], result.stderr[-2000:])
    return result.stdout


def fixture(directory):
    """Fresh search directories: denied/seedchild (0644), allowed/seedchild."""
    for name, mode in (('allowed', 0o755), ('denied', 0o644)):
        (directory / name).mkdir(parents=True)
        shutil.copyfile(child, directory / name / 'seedchild')
        (directory / name / 'seedchild').chmod(mode)
    return directory


identity = run(CC + ['--print-source-hash']).decode().strip()
child = OUT / 'process-api-child'
run(CC + ['-o', child, TESTS / 'process-api-child.c'])
production = {}
for name in ['process-api-check', 'wait-macros-check', 'strerror-check']:
    production[name] = OUT / ('forth-' + name)
    run(CC + ['-o', production[name], TESTS / (name + '.c')])
expected = b'process API contracts passed\n'
assert run([production['process-api-check'], child, fixture(OUT / 'forth-files')]) == expected
facts = {name: run([production[name]]) for name in ['wait-macros-check', 'strerror-check']}
assert len(facts['wait-macros-check'].splitlines()) == 65536 + 9
report = {'compiler_source_identity': identity, 'production_contracts_passed': True,
          'production_toolchain': 'unchanged 1772-byte seed; Forth preprocessing, compilation and linking',
          'child_program': 'Forth-built process-api-child for every exec in every build',
          'memory_limit_bytes': LIMIT, 'parallel_jobs': 1, 'host_oracles': []}
host = shutil.which('gcc')
assert host, 'GCC is required for independent O0/O2 host oracles'
strict = [host, '-std=c99', '-pedantic', '-Wall', '-Wextra', '-Werror', '-U_FORTIFY_SOURCE']
for level in ['-O0', '-O2']:
    tag = level[1:]
    oracle = OUT / ('host-process-api-' + tag)
    run(strict + [level, '-D_GNU_SOURCE', '-DPROCESS_API_HOST_ORACLE',
                  TESTS / 'process-api-check.c', '-o', oracle])
    assert run([oracle, child, fixture(OUT / ('host-files-' + tag))]) == expected
    for name in ['wait-macros-check', 'strerror-check']:
        executable = OUT / ('host-' + name + '-' + tag)
        run(strict + [level, TESTS / (name + '.c'), '-o', executable])
        assert run([executable]) == facts[name], name + ' differs from host glibc at ' + level
    report['host_oracles'].append({'optimization': level, 'libc_public_contract': True,
                                   'wait_macros_identical': True, 'strerror_identical': True})
# Host GCC lint of the runtime sources against the runtime headers alone.
# Host stdarg.h replaces the runtime's (same ABI, Forth-specific spelling).
lint = OUT / 'lint-include'
lint.mkdir()
(lint / 'stdarg.h').write_text('#include "%s/stdarg.h"\n' % run([host, '-print-file-name=include']).decode().strip())
LINT = [host, '-fsyntax-only', '-nostdinc', '-isystem', lint, '-isystem', INCLUDE,
        '-Werror=implicit-function-declaration', '-Werror=implicit-int',
        '-Wno-builtin-declaration-mismatch']
for name in ['process-api.c', 'strerror.c']:
    run(LINT + ['-Wall', '-Wextra', '-Werror', ROOT / 'runtime/gcc-seed' / name])
binutils = options.binutils_source_root.resolve()
if (binutils / 'libiberty/pex-unix.c').is_file():
    configuration = OUT / 'libiberty-config'
    configuration.mkdir()
    (configuration / 'config.h').write_text(CONFIG)
    flags = ['-DHAVE_CONFIG_H', '-I', configuration, '-I', binutils / 'include']
    objects, host_objects = [], []
    for unit in UNITS:
        source = binutils / 'libiberty' / (unit + '.c')
        run(LINT + flags + [source])
        objects.append(OUT / ('forth-' + unit + '.o'))
        run(CC + flags + ['-c', source, '-o', objects[-1]])
        host_objects.append(OUT / ('host-' + unit + '.o'))
        run([host, '-O2', '-U_FORTIFY_SOURCE', '-w'] + flags + ['-c', source, '-o', host_objects[-1]])
    run(LINT + ['-I', binutils / 'include', TESTS / 'pex-check.c'])
    consumer = OUT / 'forth-pex-check'
    run(CC + ['-I', binutils / 'include', TESTS / 'pex-check.c'] + objects + ['-o', consumer])
    directory = OUT / 'forth-pex-files'
    directory.mkdir()
    assert run([consumer, child, directory], stderr=MISSING) == b'pex contracts passed\n'
    oracle = OUT / 'host-pex-check'
    run(strict + ['-O2', '-I', binutils / 'include', TESTS / 'pex-check.c'] + host_objects + ['-o', oracle])
    directory = OUT / 'host-pex-files'
    directory.mkdir()
    assert run([oracle, child, directory], stderr=MISSING) == b'pex contracts passed\n'
    report['original_source_contract'] = {
        'source_sha256': {unit: hashlib.sha256((binutils / 'libiberty' / (unit + '.c')).read_bytes()).hexdigest()
                          for unit in UNITS},
        'config_h': CONFIG,
        'scope': 'unchanged binutils 2.30 libiberty pex units compiled and linked by Forth; '
                 'printf|tr pipeline, output file, exit/signal statuses, missing program; '
                 'no implicit declarations under host GCC lint; host GCC/glibc build of the same units agrees'}
else:
    print('SKIP: original libiberty pex proof requires the pinned binutils source')
assert identity == run(CC + ['--print-source-hash']).decode().strip(), 'compiler changed'
names = ['runtime/gcc-seed/process-api.c', 'runtime/gcc-seed/strerror.c',
         'runtime/gcc-seed/include/unistd.h', 'runtime/gcc-seed/include/sys/wait.h',
         'runtime/gcc-seed/include/signal.h', 'runtime/gcc-seed/include/string.h',
         'runtime/gcc-seed/include/errno.h', 'tests/gcc/process-api-check.c',
         'tests/gcc/process-api-child.c', 'tests/gcc/wait-macros-check.c',
         'tests/gcc/strerror-check.c', 'tests/gcc/pex-check.c', 'tests/gcc/process-api-check.py']
report['source_sha256'] = {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in names}
report['artifact_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in OUT.iterdir() if p.is_file()}
report['commands'] = commands
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS: process API production, wait macros/strerror match host glibc O0/O2, original libiberty pex')
print(OUT / 'report.json')
