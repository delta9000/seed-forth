#!/usr/bin/env python3
"""Long double data movement, conversion acceptance and invalid C constraints.

Forth-built and host-built translation units call each other in both
directions with long double named and variadic arguments, X87/MEMORY records
and the bfd.c union/va_arg pattern. Values are made by host arithmetic or
explicit bytes and compared over their ten significant bytes. Invalid scalar operations are rejected with an exact code and leave any
previous output untouched. Scalar computation has a separate GCC oracle.
"""
from pathlib import Path
import argparse, hashlib, json, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[2]
TEST = ROOT / 'tests/gcc'
CC = ROOT / 'tools/gcc-direct-cc.py'
HOST = ['gcc', '-std=gnu89', '-U_FORTIFY_SOURCE', '-Wno-psabi', '-fno-pie', '-no-pie', '-I' + str(TEST)]
FIXTURES = ['long-double.h', 'long-double-values.h', 'long-double-seed.c', 'long-double-peer.c',
            'long-double-main.c', 'long-double-forth-main.c']


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def run(command, status=0):
    p = subprocess.run([str(x) for x in command], capture_output=True, timeout=300)
    assert p.returncode == status, (command, p.returncode, p.stdout, p.stderr)
    return p


# Invalid C uses of an extended scalar retain checked diagnostics.
REJECT = {
    "integer-shift-extended": ("long double x; int f(void){return 1<<x;}",249,b"long-double: "),
    "remainder": ("long double x; void f(void){x%=1;}",249,b"long-double: "),
    "record-initializer": ("struct A{long x,y;};void f(struct A a){long double x=a;}",249,b"long-double: "),
    "pointer-initializer": ("void f(void *p){long double x=p;}",249,b"long-double: "),
    "extended-to-pointer": ("void *f(long double x){return (void *)x;}",249,b"long-double: "),
    "pointer-to-extended": ("long double f(void *x){return (long double)x;}",249,b"long-double: "),
    'complement': ('long double x; void f(void){x=~x;}', 249, b'long-double: '),
    'subscript': ('long double x; int f(int *a){return a[x];}', 249, b'long-double: '),
    'switch': ('long double x; int f(void){switch(x){default:return 0;}}', 249, b'long-double: '),
    'global-copy-initializer': ('long double x; long double g=x;', 240, b'cc: '),
    'floating-member-record': ('struct A{long double a;double d;};void f(struct A a){}', 232, b'aggregate-abi: '),
    'member-of-scalar': ('long double x; void f(void){x.a;}', 90, b'cc: line 1: error 90'),
}

# An X87 record is an unchanged unnamed argument (record-varargs-check.py runs one).
ACCEPT = {
    'record-vararg': 'struct A{long double a;};void h(int,...);void f(struct A a){h(1,a);}',
}
ACCEPT.update({
    'add': 'long double x; long double f(void){return x+x;}',
    'multiply-assign': 'long double x; void f(void){x*=x;}',
    'compound-add': 'long double x; void f(void){x+=1;}',
    'increment': 'long double x; void f(void){x++;}',
    'negate': 'long double x; void f(void){x=-x;}',
    'not': 'long double x; int f(void){return !x;}',
    'condition': 'long double x; int f(void){if(x)return 1;return 0;}',
    'logical': 'long double x; int f(void){return x&&1;}',
    'compare': 'long double x,y; int f(void){return x<y;}',
    'equal': 'long double x; int f(void){return x==x;}',
    'to-int-cast': 'long double x; int f(void){return (int)x;}',
    'to-double-cast': 'long double x; double f(void){return (double)x;}',
    'from-int-cast': 'long double f(int i){return (long double)i;}',
    'nested-cast': 'long double f(long i){return (long double)(int)i;}',
    'to-double-assign': 'long double x; double y; void f(void){y=x;}',
    'from-double-assign': 'long double x; void f(double d){x=d;}',
    'to-double-return': 'long double x; double f(void){return x;}',
    'from-int-return': 'long double f(void){return 1;}',
    'to-int-argument': 'void h(int); long double x; void f(void){h(x);}',
    'from-double-argument': 'void h(long double); void f(double d){h(d);}',
    'local-initializer': 'void f(int i){long double y=i;}',
    'mixed-conditional': 'long double x; void f(int c){long double y=c?x:1.0;}',
    'static-initializer': 'void f(void){static long double z=0;}',
    'global-initializer': 'long double g=0;',
    'static-array-initializer': 'long double g[2]={0,0};',
    'braced-element-conversion': 'void f(int i){long double a[1]={i};}',
    'literal': 'long double f(void){return 1.0L;}',
})



def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--work', type=Path)
    a = ap.parse_args()
    (ROOT / 'build-out').mkdir(exist_ok=True)
    work = (a.work or Path(tempfile.mkdtemp(prefix='long-double-', dir=ROOT / 'build-out'))).resolve()
    work.mkdir(parents=True, exist_ok=True)
    inputs = [ROOT / 'seed-forth', ROOT / '010-lib.fth', *sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),
              CC, Path(__file__), *(TEST / f for f in FIXTURES)]
    hashes = {str(p.relative_to(ROOT)): sha(p) for p in inputs}
    report = {'compiler_and_test_sha256': hashes, 'executions': [], 'rejections': {}}
    src = {f: TEST / f for f in FIXTURES}

    def execute(name, exe, expect):
        out = run([exe]).stdout
        assert out.strip() == expect, (name, out)
        report['executions'].append({'name': name, 'sha256': sha(exe)})

    # The fixtures themselves are first proved by host GCC alone.
    for opt in ('-O0', '-O2'):
        exe = work / ('oracle' + opt)
        run(HOST + [opt, src['long-double-main.c'], src['long-double-peer.c'], src['long-double-seed.c'], '-o', exe])
        execute('host-only oracle ' + opt, exe, b'long double interop ok')
        exe = work / ('oracle-forth-main' + opt)
        run(HOST + [opt, src['long-double-forth-main.c'], src['long-double-peer.c'], src['long-double-seed.c'], '-o', exe])
        execute('host-only Forth-main oracle ' + opt, exe, b'long double Forth-only ok')
    print('PASS: host GCC oracle accepts the fixtures, layouts and byte patterns', flush=True)

    seed, peer = work / 'seed.o', work / 'peer.o'
    run([CC, '-I' + str(TEST), '-c', src['long-double-seed.c'], '-o', seed])
    run([CC, '-I' + str(TEST), '-c', src['long-double-peer.c'], '-o', peer])
    exe = work / 'forth-only'
    run([CC, '-I' + str(TEST), src['long-double-forth-main.c'], seed, peer, '-o', exe])
    execute('Forth-only separate objects', exe, b'long double Forth-only ok')
    exe = work / 'forth-only-sources'
    run([CC, '-I' + str(TEST), src['long-double-forth-main.c'], src['long-double-seed.c'], src['long-double-peer.c'], '-o', exe])
    execute('Forth-only one link', exe, b'long double Forth-only ok')
    print('PASS: Forth-only named, variadic, record and bfd-union long double movement', flush=True)

    for opt in ('-O0', '-O2'):
        for name, parts in (('host peer + Forth seed', [src['long-double-peer.c'], seed]),
                            ('Forth peer + Forth seed', [peer, seed]),
                            ('Forth peer + host seed', [peer, src['long-double-seed.c']])):
            exe = work / ('interop-' + name.replace(' ', '').replace('+', '-') + opt)
            run(HOST + [opt, src['long-double-main.c'], *parts, '-o', exe])
            execute(name + ' ' + opt, exe, b'long double interop ok')
    print('PASS: host O0/O2 inbound and outbound calls, X87 st(0) results and sixteen-byte stack slots', flush=True)

    for name, (body, status, prefix) in REJECT.items():
        c = work / (name + '.c')
        c.write_text(body + '\n')
        out = work / (name + '.o')
        for existing in (False, True):
            out.unlink(missing_ok=True)
            if existing:
                out.write_bytes(b'previous-object\x00\xff')
            p = run([CC, '-c', c, '-o', out], status)
            assert p.stderr.startswith(prefix), (name, p.stderr)
            if status != 248:
                assert ('error ' + str(status)).encode() in p.stderr, (name, p.stderr)
            assert out.read_bytes() == b'previous-object\x00\xff' if existing else not out.exists()
        report['rejections'][name] = status
    print('PASS: %d unsupported long double operations rejected with exact codes; outputs preserved'
          % len(REJECT), flush=True)
    for name, body in ACCEPT.items():
        c = work / (name + '.c')
        c.write_text(body + '\n')
        run([CC, '-c', c, '-o', work / (name + '.o')], 0)
        report.setdefault('accepted', []).append(name)

    assert hashes == {str(p.relative_to(ROOT)): sha(p) for p in inputs}, 'inputs changed during proof'
    (work / 'report.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(work / 'report.json')


if __name__ == '__main__':
    main()
