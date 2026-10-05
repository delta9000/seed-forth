#!/usr/bin/env python3
"""Function parameter adjustment, recursive signatures, and mixed SysV ABI."""
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
(ROOT / 'build-out').mkdir(exist_ok=True)
WORK = Path(tempfile.mkdtemp(prefix='function-parameter-', dir=ROOT / 'build-out'))
ROWS = []
CC = os.environ.get('CC', 'gcc')


def run(label, command, expected=0):
    def limits():
        os.setsid()
        resource.setrlimit(resource.RLIMIT_AS, (1024**3, 1024**3))
        resource.setrlimit(resource.RLIMIT_CPU, (180, 180))
    start = time.monotonic()
    with (WORK / (label + '.stdout')).open('wb') as out, (WORK / (label + '.stderr')).open('wb') as err:
        proc = subprocess.Popen(list(map(str, command)), cwd=ROOT, stdout=out, stderr=err, preexec_fn=limits)
        try:
            code = proc.wait(timeout=200)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            code = proc.wait()
    ROWS.append({'name': label, 'command': list(map(str, command)), 'returncode': code,
                 'expected': expected, 'seconds': time.monotonic() - start})
    (WORK / 'results.json').write_text(json.dumps(ROWS, indent=2) + '\n')
    assert code == expected, (label, code, expected, (WORK / (label + '.stderr')).read_text())


provider = ROOT / 'tests/gcc/function-parameter-provider.c'
main = ROOT / 'tests/gcc/function-parameter-main.c'
for name, source in [('provider', provider), ('main', main)]:
    run(name + '-c90', [CC, '-std=c90', '-pedantic-errors', '-fsyntax-only', source])
    run(name + '-forth', ['python3', ROOT / 'tools/gcc-direct-cc.py', '-c', source, '-o', WORK / (name + '.o')])
for opt in ['-O0', '-O2']:
    run('host-provider' + opt, [CC, '-std=c90', '-pedantic-errors', opt, '-fno-pie', '-c', provider, '-o', WORK / ('provider' + opt + '.o')])
    run('host-main' + opt, [CC, '-std=c90', '-pedantic-errors', opt, '-fno-pie', '-c', main, '-o', WORK / ('main' + opt + '.o')])
    for tag, objects in [('host', [WORK / ('provider' + opt + '.o'), WORK / ('main' + opt + '.o')]),
                         ('forth-provider', [WORK / 'provider.o', WORK / ('main' + opt + '.o')]),
                         ('forth-main', [WORK / ('provider' + opt + '.o'), WORK / 'main.o'])]:
        exe = WORK / (tag + opt)
        run(tag + '-link' + opt, [CC, '-no-pie', *objects, '-o', exe])
        run(tag + '-execute' + opt, [exe])
# One translation unit has no runtime dependency: direct Forth ELF and execution.
combined = WORK / 'combined.c'
main_text = main.read_text()
main_text = main_text.replace('struct graph { int value; };\n', '').replace('struct edge { int value; };\n', '')
combined.write_text(provider.read_text() + main_text)
run('all-forth-compile', [ROOT / 'tests/gcc/sysv-compile.sh', combined, WORK / 'all-forth'])
run('all-forth-execute', [WORK / 'all-forth'])

reject = {
    'return-width': (237, 'int f(int cb(int)); int f(long (*cb)(int));'),
    'return-pointer': (237, 'int f(int *cb(int)); int f(int (*cb)(int));'),
    'return-signedness': (237, 'int f(unsigned int cb(int)); int f(int (*cb)(int));'),
    'parameter-width': (237, 'int f(int cb(long)); int f(int (*cb)(int));'),
    'parameter-depth': (237, 'int f(int cb(char **)); int f(int (*cb)(char *));'),
    'parameter-tag': (237, 'struct A{int x;}; struct B{int x;}; int f(int cb(struct A *)); int f(int (*cb)(struct B *));'),
    'nested-signature': (237, 'int f(int cb(int nested(long))); int f(int (*cb)(int (*nested)(int)));'),
    'callback-varargs': (237, 'int f(int cb(int,...)); int f(int (*cb)(int));'),
    'callback-arity': (237, 'int f(int cb(int,int)); int f(int (*cb)(int));'),
    'callback-call-count': (235, 'int f(int cb(int)){return cb();}'),
    'outer-storage': (233, 'int f(static int cb(int));'),
    'nested-storage': (233, 'int f(int cb(extern int));'),
    'nested-register': (233, 'int f(int cb(register register int));'),
    'outer-register': (233, 'int f(register int register cb(int));'),
    'nested-duplicate-name': (233, 'int f(int cb(int x,int x));'),
    'outer-duplicate-name': (233, 'int f(int cb(int),int cb(int));'),
    'trailing-void': (233, 'int f(int cb(int,void));'),
    'knr-width': (237, 'int f(int (*)(long)); int f(cb) int cb(int); {return cb(1);}'),
    'knr-storage': (233, 'int f(cb) static int cb(int); {return cb(1);}'),
    'knr-duplicate': (233, 'int f(cb) int cb(int); int cb(int); {return cb(1);}'),
    'array-of-functions': (238, 'int f(int cb[2](int));'),
    'unnamed-definition': (233, 'int f(int (*)(int)){return 0;}'),
}
for label, (code, source) in reject.items():
    src = WORK / (label + '.c')
    src.write_text(source + '\n')
    run(label + '-gcc-reject', [CC, '-std=c90', '-pedantic-errors', '-fsyntax-only', src], 1)
    out = WORK / (label + '.o')
    marker = b'previous object must survive\n'
    out.write_bytes(marker)
    cmd = ['python3', ROOT / 'tools/gcc-direct-cc.py', '-c', src, '-o', out]
    run(label + '-existing', cmd, code)
    assert out.read_bytes() == marker, (label, 'existing output changed')
    out.unlink()
    run(label + '-absent', cmd, code)
    assert not out.exists(), (label, 'failed output was published')

(WORK / 'source-pins.json').write_text(json.dumps({str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in [ROOT / '121-cc-sysv.fth', provider, main]}, indent=2) + '\n')
print('PASS: function parameter adjustment; recursive signatures; C90; bidirectional GCC O0/O2 and all-Forth execution')
print('PASS: %d signature/storage/shape rejection cases preserve existing and absent outputs' % len(reject))
print('PENDING: function-parameter-ranked-composition.c requires the separate ranked-array repair')
print(WORK / 'results.json')
