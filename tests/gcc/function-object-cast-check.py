#!/usr/bin/env python3
"""Explicit function/object pointer casts keep all 64 bits; other crossings reject.

Host GCC (-std=gnu89, O0/O2) is only the semantic oracle. Production
compilation and linking use tools/gcc-direct-cc.py.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
(ROOT / 'build-out').mkdir(exist_ok=True)
WORK = Path(tempfile.mkdtemp(prefix='function-object-cast-', dir=ROOT / 'build-out'))
CC = os.environ.get('CC', 'gcc')
FIXTURE = ROOT / 'tests/gcc/function-object-cast.c'


def run(command, expected=0):
    proc = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=300)
    assert proc.returncode == expected, (command, proc.returncode, expected, proc.stderr.decode(errors='replace'))
    return proc


run(['python3', ROOT / 'tools/gcc-direct-cc.py', FIXTURE, '-o', WORK / 'forth'])
forth = run([WORK / 'forth']).stdout
assert b'failures 0\n' in forth and b'interpreter 30 19 49' in forth, forth
for opt in ['-O0', '-O2']:
    exe = WORK / ('host' + opt)
    run([CC, '-std=gnu89', '-U_FORTIFY_SOURCE', opt, FIXTURE, '-o', exe])
    assert run([exe]).stdout == forth, (opt, forth)
print('PASS: function<->void*/char*/struct*/T(**)() round trips, static initializers and chew-style dictionary slots match GCC O0/O2')

# Implicit function/object conversions keep their existing diagnostics (237);
# only explicit casts changed. Non-pointer partners still reject.
reject = {
    'function-to-int': (230, 'int f(int);int g(void){return (int)f;}'),
    'function-to-unsigned': (230, 'int f(int);unsigned g(void){return (unsigned)f;}'),
    'function-to-double': (230, 'int f(int);double g(void){return (double)f;}'),
    'double-to-function': (230, 'int g(double d){return ((int (*)(int))d)(1);}'),
    'static-function-to-short': (230, 'int f(int);short s=(short)f;'),
    'object-cast-call': (230, 'int f(int);int g(void){return ((int (**)(int))f)(1);}'),
    'function-to-struct': (232, 'struct S{int a;};int f(int);int g(void){return ((struct S)f).a;}'),
    'union-to-function': (232, 'union U{int a;};int g(union U u){return ((int (*)(int))u)(1);}'),
    'implicit-char-to-function': (237, 'char c;int (*p)(int)=&c;'),
    'implicit-function-to-struct-pointer': (237, 'struct S{int a;};int f(int);int g(void){struct S *s;s=f;return s!=0;}'),
    'implicit-argument': (237, 'int h(int (*)(int));int g(void){char c;return h(&c);}'),
    'implicit-conditional': (237, 'int f(int);int g(void *p){return (1?p:f)!=0;}'),
}
for label, (code, source) in reject.items():
    src = WORK / (label + '.c')
    src.write_text(source + '\n')
    for mode in ['object', 'mapped']:
        out = WORK / (label + '-' + mode)
        marker = b'previous valid artifact\x00\xff'
        out.write_bytes(marker)
        cmd = (['python3', ROOT / 'tools/gcc-direct-cc.py', '-c', src, '-o', out]
               if mode == 'object' else [ROOT / 'tests/gcc/sysv-compile.sh', src, out])
        proc = run(cmd, code)
        assert ('error %d' % code) in proc.stderr.decode(errors='replace'), (label, mode, 'missing exact diagnostic')
        assert out.read_bytes() == marker, (label, mode, 'publication')
print('PASS: %d non-pointer casts and implicit crossings reject with exact codes; outputs preserved in object and mapped modes' % len(reject))
