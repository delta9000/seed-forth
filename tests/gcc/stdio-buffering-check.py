#!/usr/bin/env python3
"""Observable stdio buffering: Forth-built program vs host-glibc oracle.

stdio-buffering-check.c is compiled by the Forth compiler against the seed
runtime (production) and by host GCC against glibc (expected behaviour
only). Each mode runs with stdout and stderr sharing one pipe, sharing one
file, and on a pseudo-terminal; the bytes and exit status must match.
With strace available, the production program's write(2) count for
100,001 single-character putchar calls is also bounded.
"""
from pathlib import Path
import hashlib
import json
import os
import pty
import random
import select
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'tests/gcc/stdio-buffering-check.c'
MODES = ['interleave', 'exit', '_exit', 'return', 'lbf', 'nbf', 'fbf', 'many']


def build(work):
    production = work / 'buffering-forth'
    oracle = work / 'buffering-glibc'
    subprocess.run([sys.executable, ROOT / 'tools/gcc-direct-cc.py', FIXTURE, '-o', production], check=True)
    subprocess.run(['gcc', '-std=gnu89', '-O1', '-w', FIXTURE, '-o', oracle], check=True)
    return production, oracle


def run_pipe(program, arguments, data=b''):
    result = subprocess.run([program] + arguments, input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=60)
    return result.returncode, result.stdout


def run_file(program, arguments, work, data=b''):
    path = work / 'combined.out'
    with open(path, 'wb') as output:
        result = subprocess.run([program] + arguments, input=data, stdout=output,
                                stderr=output, timeout=60)
    return result.returncode, path.read_bytes()


def run_pty(program, arguments, answer=None, prompt=b''):
    master, slave = pty.openpty()
    process = subprocess.Popen([program] + arguments, stdin=slave, stdout=slave, stderr=slave,
                               close_fds=True)
    os.close(slave)
    output = b''
    deadline = time.time() + 30
    answered = answer is None
    while time.time() < deadline:
        ready, _, _ = select.select([master], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
        if not answered and prompt in output:
            os.write(master, answer)
            answered = True
        if process.poll() is not None and not ready:
            break
    process.wait(timeout=30)
    os.close(master)
    return process.returncode, output, answered


def main():
    (ROOT / 'build-out').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='stdio-buffering-', dir=ROOT / 'build-out'))
    production, oracle = build(work)
    results = {}
    checks = 0

    def compare(name, left, right):
        nonlocal checks
        checks += 1
        if left != right:
            raise SystemExit(f'FAIL {name}:\n  glibc: {right!r}\n  seed:  {left!r}')
        results[name] = hashlib.sha256(repr(left).encode()).hexdigest()

    for mode in MODES:
        compare(mode + ':pipe', run_pipe(production, [mode]), run_pipe(oracle, [mode]))
        compare(mode + ':file', run_file(production, [mode], work), run_file(oracle, [mode], work))
        compare(mode + ':pty', run_pty(production, [mode]), run_pty(oracle, [mode]))
    for mode in ('update', 'sync'):
        outputs = []
        for program in (production, oracle):
            target = work / (mode + '-' + program.name)
            outputs.append(run_pipe(program, [mode, str(target)]) + (target.read_bytes(),))
        compare(mode, outputs[0], outputs[1])
    data = bytes(random.Random(20261006).getrandbits(8) for _ in range(300000))
    compare('copy:pipe', run_pipe(production, ['copy'], data), run_pipe(oracle, ['copy'], data))
    if run_pipe(production, ['copy'], data)[1] != data:
        raise SystemExit('FAIL copy: output differs from input')
    compare('headroom', run_pipe(production, ['headroom'], b'abc'), run_pipe(oracle, ['headroom'], b'abc'))
    compare('prompt:pipe', run_pipe(production, ['prompt'], b'bob\n'), run_pipe(oracle, ['prompt'], b'bob\n'))
    compare('prompt:pty', run_pty(production, ['prompt'], b'bob\n', b'name? '),
            run_pty(oracle, ['prompt'], b'bob\n', b'name? '))
    writes = None
    if shutil.which('strace'):
        trace = work / 'many.strace'
        subprocess.run(['strace', '-f', '-e', 'trace=write', '-o', trace, production, 'many'],
                       stdout=subprocess.DEVNULL, check=True, timeout=60)
        writes = sum(1 for line in trace.read_text().splitlines() if 'write(1,' in line)
        # 100,001 bytes in 8,192-byte buffers: 13 writes.
        if writes > 13:
            raise SystemExit(f'FAIL: {writes} write calls for 100,001 putchar bytes')
    report = {'proof': 'Forth-built program behaves like the host-glibc-built program',
              'host_objects_in_production': False, 'comparisons': checks,
              'putchar_write_calls': writes, 'results_sha256': results}
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS: stdio buffering, {checks} pipe/file/terminal comparisons with glibc; '
          f'{writes} writes for 100,001 putchar bytes ({work}/report.json)')


if __name__ == '__main__':
    main()
