#!/usr/bin/env python3
"""Nested function-pointer casts, object depth, and mixed SysV ABI."""
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
WORK = Path(tempfile.mkdtemp(prefix='nested-function-pointer-', dir=ROOT / 'build-out'))
ROWS = []
CC = os.environ.get('CC', 'gcc')


def run(label, command, expected=0):
    def limits():
        resource.setrlimit(resource.RLIMIT_AS, (1024**3, 1024**3))
        resource.setrlimit(resource.RLIMIT_CPU, (180, 180))
    start = time.monotonic()
    with (WORK / (label + '.stdout')).open('wb') as out, (WORK / (label + '.stderr')).open('wb') as err:
        proc = subprocess.Popen(list(map(str, command)), cwd=ROOT, stdout=out, stderr=err, preexec_fn=limits)
        try:
            code = proc.wait(timeout=200)
        except subprocess.TimeoutExpired:
            proc.kill()
            code = proc.wait()
    ROWS.append({'name': label, 'command': list(map(str, command)), 'returncode': code,
                 'expected': expected, 'seconds': time.monotonic() - start})
    (WORK / 'results.json').write_text(json.dumps(ROWS, indent=2) + '\n')
    assert code == expected, (label, code, expected, (WORK / (label + '.stderr')).read_text())


provider = ROOT / 'tests/gcc/nested-function-pointer-provider.c'
main = ROOT / 'tests/gcc/nested-function-pointer-main.c'
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
main_text = main_text.replace('struct nested_box { int (**slot[2])(int); };\n', '').replace('typedef int (*nested_callback)(int);\n', '')
combined.write_text(provider.read_text() + main_text)
run('all-forth-compile', [ROOT / 'tests/gcc/sysv-compile.sh', combined, WORK / 'all-forth'])
run('all-forth-execute', [WORK / 'all-forth'])


# Preserve the exact source-driven GCC except.c declaration shape.
except_source = ROOT / 'tests/gcc/nested-function-pointer-except.c'
for opt in ['-O0', '-O2']:
    run('except-host-build' + opt, [CC, '-std=c90', '-pedantic-errors', opt, except_source, '-o', WORK / ('except' + opt)])
    run('except-host-run' + opt, [WORK / ('except' + opt)], 42)
run('except-forth-build', [ROOT / 'tests/gcc/sysv-compile.sh', except_source, WORK / 'except-forth'])
run('except-forth-run', [WORK / 'except-forth'], 42)
reject = {
    'symbol-object-call': (230, 'int g(int (**p)(int)){return p(1);}'),
    'local-object-call': (230, 'int g(void *d){int (**p)(int)=d;return p(1);}'),
    'cast-object-call': (230, 'int g(void *d){return ((int (**)(int))d)(1);}'),
    'array-object-call': (230, 'int (**p[2])(int);int g(void){return p[0](1);}'),
    'triple-object-call': (230, 'int g(int (***p)(int)){return (*p)(1);}'),
    'typedef-object-call': (230, 'typedef int(*F)(int);int g(F *p){return p(1);}'),
    'wrong-call-count': (235, 'int g(void *d){return (*(int (**)(int))d)();}'),
    'wrong-call-count-three': (235, 'int g(void *d){return (**(int (***)(int))d)(1,2);}'),
    'wrong-return-width': (237, 'int g(int (**)(int));int g(long (**p)(int));'),
    'wrong-parameter-width': (237, 'int g(int (**)(int));int g(int (**p)(long));'),
    'wrong-depth': (237, 'int g(int (**)(int));int g(int (***p)(int));'),
    'wrong-varargs': (237, 'int g(int (**)(int,...));int g(int (**p)(int));'),
    'wrong-nested-signature': (237, 'int g(int (**)(int (*)(long)));int g(int (**p)(int (*)(int)));'),
    'wrong-tag': (237, 'struct A{int x;};struct B{int x;};int g(int (**)(struct A*));int g(int (**p)(struct B*));'),
    'wrong-store-depth': (237, 'int g(void *d,int (***p)(int)){*(int (**)(int))d=p;return 0;}'),
    'wrong-store-signature': (237, 'int g(void *d,long (*p)(int)){*(int (**)(int))d=p;return 0;}'),
    'function-object-cast-call': (230, 'int f(int);int g(void){return ((int (**)(int))f)(1);}'),
    'function-double-cast': (230, 'int f(int);double g(void){return (double)f;}'),
    'double-function-cast': (230, 'int g(double d){return ((int (*)(int))d)(1);}'),
    'function-return-function': (238, 'int (f(void))(int);'),
    'function-return-array': (238, 'int (*f(void))[3];'),
    'array-of-functions': (238, 'int f[3](int);'),
    'unsupported-grouped-return': (238, 'int (**f(void))(int);'),
    'qualified-array': (238, 'int g(void*d){return sizeof(int (*const *)[2]);}'),
    'named-depth-overflow': (231, 'int (' + '*'*256 + 'p)(int);'),
    'cast-depth-overflow': (231, 'int g(void*d){return sizeof(int (' + '*'*256 + ')(int));}'),
}
for label, (code, source) in reject.items():
    src = WORK / (label + '.c')
    src.write_text(source + '\n')
    for mode in ['object', 'mapped']:
        out = WORK / (label + '-' + mode)
        marker = b'previous valid artifact\x00\xff'
        for exists in [True, False]:
            if exists:
                out.write_bytes(marker)
            else:
                out.unlink(missing_ok=True)
            cmd = (['python3', ROOT / 'tools/gcc-direct-cc.py', '-c', src, '-o', out]
                   if mode == 'object' else [ROOT / 'tests/gcc/sysv-compile.sh', src, out])
            run(label + '-' + mode + ('-existing' if exists else '-absent'), cmd, code)
            assert out.read_bytes() == marker if exists else not out.exists(), (label, mode, 'publication')
            log = WORK / (label + '-' + mode + ('-existing' if exists else '-absent') + '.stderr')
            assert 'error ' + str(code) in log.read_text(), (label, 'missing exact diagnostic')
            assert not (WORK / (log.stem + '.stdout')).read_bytes(), (label, 'compiler stdout')
# The eight-bit type encoding must not wrap; depth255 itself remains usable.
deep = WORK / 'depth255.c'
deep.write_text('int (' + '*'*255 + 'p)(int);int main(void){return sizeof(p)==8 && sizeof(int (' + '*'*255 + ')(int))==8 ? 0 : 1;}\n')
run('depth255-gcc', [CC, '-std=c90', '-pedantic-errors', '-fsyntax-only', deep])
run('depth255-forth', [ROOT / 'tests/gcc/sysv-compile.sh', deep, WORK / 'depth255'])
run('depth255-execute', [WORK / 'depth255'])
(WORK / 'source-pins.json').write_text(json.dumps({str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
    for p in [ROOT / '121-cc-sysv.fth', provider, main]}, indent=2) + '\n')
print('PASS: strict C90, bidirectional GCC O0/O2 and Forth-only execution')
print('PASS: %d shape/call/cast rejections; exact diagnostics; existing and absent outputs in object and mapped modes' % len(reject))
print(WORK / 'results.json')
