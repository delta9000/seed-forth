#!/usr/bin/env python3
"""Long double as an x87 data-movement type; host GCC is only an ABI oracle.

Forth-built and host-built translation units call each other in both
directions with long double named and variadic arguments, X87/MEMORY records
and the bfd.c union/va_arg pattern. Values are made by host arithmetic or
explicit bytes and compared over their ten significant bytes. Every
operation that would need x87 computation is rejected with an exact code and
leaves any previous output untouched.
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


# name: (source, exit status, stderr prefix). 249 is this layer's boundary.
REJECT = {
    'add': ('long double x; long double f(void){return x+x;}', 249, b'long-double: '),
    'multiply-assign': ('long double x; void f(void){x*=x;}', 249, b'long-double: '),
    'compound-add': ('long double x; void f(void){x+=1;}', 249, b'long-double: '),
    'increment': ('long double x; void f(void){x++;}', 249, b'long-double: '),
    'negate': ('long double x; void f(void){x=-x;}', 249, b'long-double: '),
    'complement': ('long double x; void f(void){x=~x;}', 249, b'long-double: '),
    'not': ('long double x; int f(void){return !x;}', 249, b'long-double: '),
    'condition': ('long double x; int f(void){if(x)return 1;return 0;}', 249, b'long-double: '),
    'logical': ('long double x; int f(void){return x&&1;}', 249, b'long-double: '),
    'compare': ('long double x,y; int f(void){return x<y;}', 249, b'long-double: '),
    'equal': ('long double x; int f(void){return x==x;}', 249, b'long-double: '),
    'subscript': ('long double x; int f(int *a){return a[x];}', 249, b'long-double: '),
    'switch': ('long double x; int f(void){switch(x){default:return 0;}}', 249, b'long-double: '),
    'to-int-cast': ('long double x; int f(void){return (int)x;}', 249, b'long-double: '),
    'to-double-cast': ('long double x; double f(void){return (double)x;}', 249, b'long-double: '),
    'from-int-cast': ('long double f(int i){return (long double)i;}', 249, b'long-double: '),
    'nested-cast': ('long double f(long i){return (long double)(int)i;}', 249, b'long-double: '),
    'to-double-assign': ('long double x; double y; void f(void){y=x;}', 249, b'long-double: '),
    'from-double-assign': ('long double x; void f(double d){x=d;}', 249, b'long-double: '),
    'to-double-return': ('long double x; double f(void){return x;}', 249, b'long-double: '),
    'from-int-return': ('long double f(void){return 1;}', 249, b'long-double: '),
    'to-int-argument': ('void h(int); long double x; void f(void){h(x);}', 249, b'long-double: '),
    'from-double-argument': ('void h(long double); void f(double d){h(d);}', 249, b'long-double: '),
    'local-initializer': ('void f(int i){long double y=i;}', 249, b'long-double: '),
    'mixed-conditional': ('long double x; void f(int c){long double y=c?x:1.0;}', 249, b'long-double: '),
    'static-initializer': ('void f(void){static long double z=0;}', 249, b'long-double: '),
    'global-initializer': ('long double g=0;', 249, b'long-double: '),
    'global-copy-initializer': ('long double x; long double g=x;', 249, b'long-double: '),
    'static-array-initializer': ('long double g[2]={0,0};', 249, b'long-double: '),
    'braced-element-conversion': ('void f(int i){long double a[1]={i};}', 249, b'long-double: '),
    'literal': ('long double f(void){return 1.0L;}', 248, b'cc-f64-literal: suffix-unsupported'),
    'record-vararg': ('struct A{long double a;};void h(int,...);void f(struct A a){h(1,a);}', 232, b'cc: line 1: error 232'),
    'floating-member-record': ('struct A{long double a;double d;};void f(struct A a){}', 232, b'aggregate-abi: '),
    'member-of-scalar': ('long double x; void f(void){x.a;}', 90, b'cc: line 1: error 90'),
}


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

    assert hashes == {str(p.relative_to(ROOT)): sha(p) for p in inputs}, 'inputs changed during proof'
    (work / 'report.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(work / 'report.json')


if __name__ == '__main__':
    main()
