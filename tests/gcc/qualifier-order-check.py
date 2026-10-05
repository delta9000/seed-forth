#!/usr/bin/env python3
"""Declaration specifiers in any C90 order and casts of qualified arrays.

The Forth driver builds every target byte. Host GCC (-std=c90) is used only
as an oracle for the fixture's printed results and to link one object.
"""
from pathlib import Path
import json, os, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[2]
CC = ROOT / 'tools/gcc-direct-cc.py'
FIXTURE = ROOT / 'tests/gcc/qualifier-order-fixture.c'

# Accepted spellings: every declaration context and type-name context.
ACCEPT = {
    'file-unsigned-const-char': 'unsigned const char x;',
    'file-long-const-int': 'long const int x;',
    'file-const-unsigned-long': 'const unsigned long x;',
    'file-static-const-unsigned': 'static const unsigned x;',
    'file-volatile-unsigned-short': 'volatile unsigned short x;',
    'file-char-const-pointer': 'char const *x;',
    'file-all-interleaved': 'int const long volatile unsigned x;',
    'file-long-long-split': 'long const long unsigned x;',
    'file-double-long': 'double const long x;',
    'typedef-const-before': 'typedef unsigned long size_t; const size_t x;',
    'typedef-const-after': 'typedef unsigned long size_t; size_t const x;',
    'typedef-declaration': 'typedef unsigned const char Byte; Byte b;',
    'block-scope': 'int f(void){unsigned const char c=1;long volatile int v=2;static short const unsigned s=3;return c+v+s;}',
    'parameter': 'int f(unsigned const char a, register long const b, unsigned register const c);',
    'parameter-definition': 'int f(unsigned const char a, long const int b){return a+b;}',
    'member': 'struct S{unsigned const char a;long volatile int b;short const unsigned c;};',
    'sizeof-type-name': 'int f(void){return sizeof(unsigned const char)+sizeof(long volatile int);}',
    'cast-type-name': 'int f(void){return (unsigned const char)300;}',
    'constant-sizeof': 'char a[sizeof(short const unsigned)];',
    'cast-const-typedef-pointer': 'typedef unsigned T;T t[2];const T *f(void){return (const T *)t;}',
    'cast-typedef-const-pointer': 'typedef unsigned T;T t[2];const T *f(void){return (T const *)t;}',
    'cast-const-pointer-const-pointer': 'typedef unsigned T;const T *p;const T *const *f(void){return (const T * const *)&p;}',
    'cast-volatile-typedef-pointer': 'typedef unsigned T;T t[2];void *f(void){return (volatile T *)t;}',
    'sizeof-qualified-typedef-pointers': 'typedef unsigned T;int f(void){return sizeof(const T *)+sizeof(T const *)+sizeof(const T * const *)+sizeof(volatile T *);}',
    'cast-qualified-matrix': 'typedef unsigned T;static const T t[8][256];const T *f(void){return (const T *)t;}',
    'cast-qualified-matrix-void': 'static const long t[2][3];void *f(void){return (void *)t;}',
    'cast-qualified-ranked-array': 'static const unsigned char t[2][3][4];const unsigned char *f(void){return (const unsigned char *)t;}',
    'cast-qualified-row-typedef': 'typedef const int Row[2];Row t[2];const int *f(void){return (const int *)t;}',
    'cast-qualified-matrix-explicit-row': 'const long t[2][3];long f(void){long (*p)[3]=(long (*)[3])t;return p[1][2];}',
    'qualified-matrix-index': 'const long t[2][3];long f(void){return t[1][2]+*t[1];}',
    # Qualified arrays decay in every value context, not only under a cast;
    # see tests/gcc/qualified-array-check.py.
    'qualified-matrix-const-initializer': 'const long t[2][3];long f(void){const long (*p)[3]=t;return p[0][0];}',
    'qualified-matrix-return': 'const long t[2][3];void *f(void){return t;}',
    'qualified-matrix-arithmetic': 'const long t[2][3];void *f(void){return (void *)(t+1);}',
    'qualified-matrix-address': 'const long t[2][3];void *f(void){return (void *)&t[0];}',
    'qualified-array-pointer-type': 'const long t[2][3];void *f(void){return (const long (*)[3])t;}',
    'qualified-matrix-static-cast': 'typedef unsigned T;static const T t[2][2];static const T *p=(const T *)t;',
}

# Rejections keep their existing diagnostics.
REJECT = {
    'unsigned-signed': ('unsigned signed int x;', 233),
    'signed-const-unsigned': ('signed const unsigned x;', 233),
    'long-char': ('long char x;', 233),
    'long-const-char': ('long const char x;', 233),
    'short-long': ('short long x;', 233),
    'long-long-long': ('long long const long x;', 233),
    'int-int': ('int const int x;', 233),
    'char-char': ('char char x;', 233),
    'void-int': ('void int *x;', 233),
    'signed-void': ('signed void *x;', 233),
    'unsigned-double': ('unsigned double x;', 233),
    'long-float': ('long float x;', 233),
    'long-long-double': ('long long double x;', 233),
    'float-int': ('float int x;', 233),
    'block-long-char': ('int f(void){long char c;return 0;}', 233),
    'member-short-char': ('struct S{short char c;};', 233),
    'parameter-int-int': ('int f(int const int a);', 233),
    'sizeof-short-char': ('int f(void){return sizeof(short const char);}', 233),
    'cast-long-void': ('int f(void){return (long void *)0!=0;}', 233),
    'register-twice': ('int f(register const register int a);', 233),
    'typedef-then-keyword': ('typedef int T; T int x;', 203),
    'unsigned-aggregate': ('struct s{int a;}; unsigned struct s x;', 203),
    'unsigned-typedef': ('typedef int T; unsigned T x;', 237),
    # A qualified matrix decays to a pointer to qualified rows; storing it
    # in an unqualified row pointer would discard the qualifier.
    'qualified-matrix-initializer': ('const long t[2][3];long f(void){long (*p)[3]=t;return p[0][0];}', 238),
}

env = os.environ.copy()
env['LC_ALL'] = 'C'
env['PYTHONWARNINGS'] = "ignore:'maxsplit' is passed as positional argument:DeprecationWarning"


def run(args, timeout=300):
    return subprocess.run([str(a) for a in args], capture_output=True, env=env, timeout=timeout)


def main():
    work = Path(tempfile.mkdtemp(prefix='qualifier-order-'))
    results = []

    def record(name, ok, **info):
        results.append({'name': name, 'pass': bool(ok), **info})

    # Fixture: Forth-linked and Forth-object executables against host GCC.
    expected = None
    for opt in ('-O0', '-O2'):
        exe = work / ('host' + opt)
        p = run(['gcc', '-std=c90', opt, '-U_FORTIFY_SOURCE', FIXTURE, '-o', exe])
        q = run([exe]) if p.returncode == 0 else None
        out = q.stdout.decode() if q else None
        if expected is None:
            expected = out
        record('host' + opt, p.returncode == 0 and q.returncode == 0 and out == expected,
               stderr=p.stderr.decode())
    for mode in ('linked', 'object'):
        exe = work / mode
        if mode == 'linked':
            p = run([sys.executable, CC, FIXTURE, '-o', exe])
        else:
            obj = work / 'fixture.o'
            p = run([sys.executable, CC, '-c', FIXTURE, '-o', obj])
            if p.returncode == 0:
                p = run(['gcc', '-fno-pie', '-no-pie', obj, '-o', exe])
        q = run([exe]) if p.returncode == 0 else None
        out = q.stdout.decode() if q else None
        record('fixture-' + mode, q is not None and q.returncode == 0 and out == expected,
               compile=p.returncode, stdout=out, stderr=p.stderr.decode())

    for name, src in ACCEPT.items():
        c = work / (name + '.c'); o = work / (name + '.o'); c.write_text(src + '\n')
        p = run([sys.executable, CC, '-c', c, '-o', o])
        record('accept-' + name, p.returncode == 0 and o.exists(),
               actual=p.returncode, stderr=p.stderr.decode())

    sentinel = b'preserve-existing-output\n'
    for name, (src, code) in REJECT.items():
        c = work / (name + '.c'); o = work / (name + '.o'); c.write_text(src + '\n')
        o.write_bytes(sentinel)
        p = run([sys.executable, CC, '-c', c, '-o', o])
        record('reject-' + name, p.returncode == code and o.read_bytes() == sentinel,
               expected=code, actual=p.returncode, stderr=p.stderr.decode())

    failed = [r for r in results if not r['pass']]
    print(json.dumps({'passed': len(results) - len(failed), 'total': len(results),
                      'failures': failed}, indent=2))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
