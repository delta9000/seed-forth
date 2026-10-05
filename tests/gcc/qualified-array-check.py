#!/usr/bin/env python3
"""Qualified arrays decay in every value context; row qualifiers persist.

A const or volatile array (or an array member reached through a qualified
record) decays to a pointer to qualified elements, and `&a` points to a
qualified array. A matrix's row node records the qualifier, so implicitly
discarding it (`long (*p)[3] = t` for `const long t[2][3]`) still rejects
with 238 and leaves an existing output file untouched.

The Forth driver builds every target byte. Host GCC (-std=gnu89) is used
only as an oracle for the fixture's printed results and to link one object.
"""
from pathlib import Path
import json, os, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[2]
CC = ROOT / 'tools/gcc-direct-cc.py'
FIXTURE = ROOT / 'tests/gcc/qualified-array-fixture.c'

ACCEPT = {
    # binutils 2.30 bfd/elflink.c ext32l_r_offset and its reduction.
    'elflink-reduction': 'typedef struct{unsigned char r_offset[4];}R; int main(void){R r;const R *p=&r;return (unsigned char*)&p->r_offset!=r.r_offset;}',
    'elflink-union': 'typedef struct{unsigned char r_offset[4];}R; unsigned f(const void *p){union u{unsigned v;unsigned char c[4];};const union u *a=(const union u *)&((const R *)p)->r_offset;return a->c[0];}',
    'member-decay': 'struct S{long a[2];};const long *f(const struct S *s){return s->a;}',
    'member-address': 'struct S{long a[2];};typedef const long (*P)[2];P f(const struct S *s){return &s->a;}',
    'nested-member': 'struct T{struct{short v[3];}in;};int f(const struct T *t){const short *p=t->in.v;return p[1];}',
    'matrix-initializer': 'const long t[2][3];long f(void){const long (*p)[3]=t;return p[0][0];}',
    'matrix-assignment': 'const long t[2][3];long f(void){const long (*p)[3];p=t+1;return p[0][0];}',
    'matrix-return-void': 'const long t[2][3];void *f(void){return t;}',
    'matrix-return-row': 'typedef const long (*P)[3];const long t[2][3];P f(void){return t;}',
    'matrix-arithmetic': 'const long t[2][3];void *f(void){return (void *)(t+1);}',
    'matrix-element-address': 'const long t[2][3];void *f(void){return (void *)&t[0];}',
    'matrix-row-pointer-cast': 'const long t[2][3];void *f(void){return (const long (*)[3])t;}',
    'matrix-argument': 'void g(const long (*)[3]);const long t[2][3];void f(void){g(t);}',
    'matrix-volatile-argument': 'void g(volatile long (*)[3]);volatile long t[2][3];void f(void){g(t);}',
    'matrix-compare': 'const long t[2][3];int f(const long (*p)[3]){return p==t||p<t+1;}',
    'matrix-subtract': 'const long t[2][3];long f(const long (*p)[3]){return p-t;}',
    'matrix-add-qualifier': 'long t[2][3];long f(void){const long (*p)[3]=t;return p[1][1];}',
    'array-address': 'const long a[3];long f(void){const long (*p)[3]=&a;return (*p)[1];}',
    'array-address-void': 'const long a[3];void *f(void){return &a;}',
    'ranked-decay': 'const unsigned char c[2][3][4];int f(void){const unsigned char (*p)[3][4]=c;return p[1][2][3];}',
    'two-dimensional-parameter': 'long f(const long a[2][3]){const long (*p)[3]=a;return p[1][2];}',
    'typedef-row': 'typedef long Row[3];const Row t[2];long f(void){const Row *p=t;return (*p)[0];}',
    'typedef-qualified-row': 'typedef const long Row[3];Row t[2];long f(void){const long (*p)[3]=t;Row *q=p;return (*q)[0];}',
    'pointer-qualified-only': 'long (*const q)[3];long f(void){long (*p)[3]=q;return p[0][0];}',
    'static-decay': 'static const long t[2][3];static const long (*p)[3]=t;',
    'static-address': 'static const long a[3];static const long (*p)[3]=&a;',
    'static-element': 'static const long t[2][3];static const long *p=&t[1][2];',
    'static-cast': 'typedef unsigned T;static const T t[2][2];static const T *p=(const T *)t;',
    'static-ranked': 'static const unsigned char c[2][3][4];static const unsigned char (*p)[3][4]=c;',
    'static-void': 'static const long t[2][3];static const void *p=t;',
    'static-record-member': 'struct S{long a[2];};const long (*p)[2]=&(*(const struct S*)0).a;',
    'matrix-conditional': 'int f(int c,const int (*p)[3],const int (*q)[3]){return (c?p:q)[0][0];}',
    'matrix-mixed-conditional': 'const long t[2][3];long u[2][3];long f(int c){const long (*p)[3]=c?u:t;return p[0][0];}',
    'middle-pointer-qualifier': 'int g(void){return sizeof(int (*const *)[2]);}',
    'sizeof': 'const long t[2][3];int f(void){return sizeof t+sizeof t[0]+sizeof &t+sizeof(const long (*)[3]);}',
}

# Discarding a row qualifier without a cast keeps its diagnostic.
REJECT = {
    'discard-initializer': ('const long t[2][3];long f(void){long (*p)[3]=t;return p[0][0];}', 238),
    'discard-assignment': ('const long t[2][3];long f(void){long (*p)[3];p=t;return p[0][0];}', 238),
    'discard-return': ('typedef long (*P)[3];const long t[2][3];P f(void){return t;}', 238),
    'discard-argument': ('void g(long (*)[3]);const long t[2][3];void f(void){g(t);}', 238),
    'discard-volatile': ('volatile long t[2][3];long f(void){long (*p)[3]=t;return p[0][0];}', 238),
    'discard-address': ('const long a[3];long f(void){long (*p)[3]=&a;return (*p)[0];}', 238),
    'discard-member-address': ('typedef struct{unsigned char r[4];}R;int f(const R *p){unsigned char (*q)[4]=&p->r;return (*q)[0];}', 238),
    'discard-declared-pointer': ('const long (*p)[3];long f(void){long (*q)[3]=p;return q[0][0];}', 238),
    'discard-cast-result': ('const long t[2][3];long f(void){long (*p)[3]=(const long (*)[3])t;return p[0][0];}', 238),
    'discard-static': ('static const long t[2][3];static long (*p)[3]=t;', 238),
    'discard-static-address': ('static const long a[3];static long (*p)[3]=&a;', 238),
    'discard-static-ranked': ('static const unsigned char c[2][3][4];static unsigned char (*p)[3][4]=c;', 238),
    'discard-parameter': ('long f(const long a[2][3]){long (*p)[3]=a;return p[0][0];}', 238),
    'discard-conditional-left': ('const long t[2][3];long u[2][3];long f(int c){long (*p)[3]=c?t:u;return p[0][0];}', 238),
    'discard-conditional-right': ('const long t[2][3];long u[2][3];long f(int c){long (*p)[3]=c?u:t;return p[0][0];}', 238),
    # A shape mismatch is still a shape error, whatever the qualifiers.
    'incompatible-row': ('const long t[2][3];long f(void){const long (*p)[4]=t;return p[0][0];}', 237),
}

env = os.environ.copy()
env['LC_ALL'] = 'C'
env['PYTHONWARNINGS'] = "ignore:'maxsplit' is passed as positional argument:DeprecationWarning"


def run(args, timeout=300):
    return subprocess.run([str(a) for a in args], capture_output=True, env=env, timeout=timeout)


def main():
    work = Path(tempfile.mkdtemp(prefix='qualified-array-'))
    results = []

    def record(name, ok, **info):
        results.append({'name': name, 'pass': bool(ok), **info})

    expected = None
    for opt in ('-O0', '-O2'):
        exe = work / ('host' + opt)
        p = run(['gcc', '-std=gnu89', opt, '-U_FORTIFY_SOURCE', FIXTURE, '-o', exe])
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
