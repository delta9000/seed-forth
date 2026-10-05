#!/usr/bin/env python3
"""Switch labels at every nesting depth, with host GCC as the oracle.

tests/gcc/switch-labels.c puts case and default labels at the top of a
switch body and inside nested if, while, do and compound statements, on
unsigned int, int, narrow, long long, unsigned long long and unsigned long
controlling expressions, with negative and out-of-range labels.  Every
label goes through 112-cc-stmt.fth's cc-switch-case, so each converts to
the promoted controlling type.  Host GCC (-std=gnu89 -U_FORTIFY_SOURCE,
-O0 and -O2) only builds the oracle and links the Forth object; the Forth
driver builds every target byte of the program under test.  Rejections
keep exact codes and preserve an existing output.
"""
from pathlib import Path
import json, os, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[2]
CC = ROOT / 'tools/gcc-direct-cc.py'
FIXTURE = ROOT / 'tests/gcc/switch-labels.c'
HOST = ['gcc', '-std=gnu89', '-U_FORTIFY_SOURCE', '-w']

# Every case is also rejected by host GCC.
REJECT = {
    'case-outside-switch': ('int f(int x){if(x){case 1:return 1;}return 0;}', 170),
    'default-outside-switch': ('int f(int x){{default:return 1;}return 0;}', 170),
    'nested-case-missing-colon': ('int f(int x){switch(x){if(x){case 1 return 1;}}return 0;}', 170),
    'top-case-missing-colon': ('int f(int x){switch(x){case 1 return 1;}return 0;}', 170),
    'nested-case-not-constant': ('int f(int x){switch(x){{case x:return 1;}}return 0;}', 240),
    'nested-case-bad-suffix': ('int f(int x){switch(x){{case 1LLL:return 1;}}return 0;}', 240),
}

env = os.environ.copy()
env['LC_ALL'] = 'C'


def run(args, timeout=300):
    return subprocess.run([str(a) for a in args], capture_output=True, env=env, timeout=timeout)


def main():
    work = Path(tempfile.mkdtemp(prefix='switch-labels-'))
    results = []

    def record(name, ok, **info):
        results.append({'name': name, 'pass': bool(ok), **info})

    expected = None
    for opt in ('-O0', '-O2'):
        exe = work / ('host' + opt)
        p = run([*HOST, opt, FIXTURE, '-o', exe])
        q = run([exe]) if p.returncode == 0 else None
        out = q.stdout.decode() if q else None
        if expected is None:
            expected = out
        record('host' + opt, q is not None and q.returncode == 0 and out == expected,
               stderr=p.stderr.decode())
    record('oracle-reviewer-case', expected is not None and expected.startswith('review 0\n'),
           stdout=expected)

    exe = work / 'forth'
    p = run([sys.executable, CC, FIXTURE, '-o', exe])
    q = run([exe]) if p.returncode == 0 else None
    out = q.stdout.decode() if q else None
    record('forth-linked', q is not None and q.returncode == 0 and out == expected,
           compile=p.returncode, stdout=out, stderr=p.stderr.decode())
    obj = work / 'fixture.o'
    p = run([sys.executable, CC, '-c', FIXTURE, '-o', obj])
    for opt in ('-O0', '-O2'):
        exe = work / ('object' + opt)
        r = run([*HOST, opt, '-no-pie', obj, '-o', exe]) if p.returncode == 0 else p
        q = run([exe]) if r.returncode == 0 else None
        out = q.stdout.decode() if q else None
        record('forth-object-host-link' + opt, q is not None and q.returncode == 0 and out == expected,
               compile=p.returncode, stdout=out, stderr=r.stderr.decode())

    sentinel = b'preserve-existing-output\n'
    for name, (src, code) in REJECT.items():
        c = work / (name + '.c'); o = work / (name + '.o'); c.write_text(src + '\n')
        host = run(['gcc', '-std=gnu89', '-fsyntax-only', c])
        o.write_bytes(sentinel)
        p = run([sys.executable, CC, '-c', c, '-o', o])
        record('reject-' + name, host.returncode != 0 and p.returncode == code
               and o.read_bytes() == sentinel,
               expected=code, actual=p.returncode, host=host.returncode,
               stderr=p.stderr.decode())

    failed = [r for r in results if not r['pass']]
    print(json.dumps({'passed': len(results) - len(failed), 'total': len(results),
                      'failures': failed}, indent=2))
    if not failed:
        print('PASS: switch labels convert at every nesting depth')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
