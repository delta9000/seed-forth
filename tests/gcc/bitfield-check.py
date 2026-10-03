#!/usr/bin/env python3
"""Forth-only bitfield/genuine fibheap proof, with optional independent host ABI oracle."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PINS = {
    'libiberty/fibheap.c': 'ded108a67c142cc605a9376e8594ca927543afc41cbecd2000dc0a3c54fba7a2',
    'include/fibheap.h': '2ffa3049878ef3f417b5763fe742824c13835ec0422c9373d6255b48ba037b99',
}
REJECTS = {
    'wide': 'struct X {unsigned x:33;};',
    'negative': 'struct X {unsigned x:-1;};',
    'zero-named': 'struct X {unsigned x:0;};',
    'long-extended': 'struct X {unsigned long x:33;};',
    'float': 'struct X {double x:3;};',
    'char': 'struct X {char x:3;};',
    'short': 'struct X {short x:3;};',
    'enum': 'enum E {A,B}; struct X {enum E x:3;};',
    'typedef-enum': 'typedef enum E {A,B} E; struct X {E x:3;};',
    'pointer': 'struct X {int *x:3;};',
    'array': 'struct X {int x[3]:3;};',
    'address': 'struct X {int x:3;}; int *f(struct X *p){return &p->x;}',
    'sizeof': 'struct X {int x:3;}; int f(struct X *p){return sizeof(p->x);}',
    'static-address': 'struct X {int x:3;} g; int *p=&g.x;',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args, expected=0):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=120)
    if result.returncode != expected:
        raise AssertionError(f'{args}: wanted {expected}, got {result.returncode}\n{result.stdout}{result.stderr}')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=ROOT/'build-out/direct-gcc-inputs/gcc-source')
    parser.add_argument('--config-dir', type=Path, help='Existing unchanged libiberty configure output')
    parser.add_argument('--oracle', action='store_true', help='Use host C only for independent ABI/layout/behavior oracles')
    parser.add_argument('--work', type=Path, help='Retain test outputs here')
    args = parser.parse_args()
    work = args.work or Path(tempfile.mkdtemp(prefix='bitfield-proof-', dir=ROOT/'build-out'))
    work.mkdir(parents=True, exist_ok=True)
    names = [ROOT/'seed-forth', ROOT/'010-lib.fth', *sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))]
    hashes = {p.name: sha(p) for p in names}
    report = {'compiler_sha256': hashes, 'host_tools_in_production': False, 'rejections': []}
    cc = ROOT/'tools/gcc-direct-cc.py'
    for name, source in REJECTS.items():
        path = work/(name+'.c'); path.write_text(source+'\n')
        obj = work/(name+'.o'); obj.write_bytes(b'preserve-existing-output')
        result = run([cc, '-c', path, '-o', obj], 248)
        assert 'bitfield:' in result.stderr and obj.read_bytes() == b'preserve-existing-output'
        report['rejections'].append(name)
    print('PASS: 14 unsupported field operations reject without replacing output')
    source = args.source_root.resolve()
    for name, expected in PINS.items():
        assert sha(source/name) == expected, 'Original source/header changed: '+name
    flags = ['-DHAVE_STDLIB_H', '-DHAVE_STRING_H', '-DHAVE_LIMITS_H']
    if args.config_dir:
        flags = ['-DHAVE_CONFIG_H', '-I'+str(args.config_dir.resolve())]
        report['configuration_sha256'] = sha(args.config_dir/'config.h')
    flags += ['-I'+str(source/'include')]
    obj = work/'fibheap.o'
    command = [cc, '-c', *flags, source/'libiberty/fibheap.c', '-o', obj]
    run(command)
    executable = work/'fibheap-proof'
    run([cc, '-I'+str(source/'include'), ROOT/'tests/gcc/bitfield-fibheap-main.c', obj, '-o', executable])
    output = run([executable]).stdout
    assert output == 'fibheap: 131 ordered extractions after union, decreases and deletions\n'
    report['fibheap'] = {'compile_command': [str(a) for a in command], 'original_sha256': PINS,
                         'object_sha256': sha(obj), 'executable_sha256': sha(executable), 'stdout': output}
    print('PASS: unchanged original fibheap unit executes with Forth-built entry, runtime and linker')
    if args.oracle:
        host = shutil.which('cc')
        assert host, 'The optional independent oracle needs host cc'
        fixture = work/'bitfield-production.o'
        run([cc, '-c', ROOT/'tests/gcc/bitfield-production.c', '-o', fixture])
        results = []
        for opt in ('-O0', '-O2'):
            binary = work/('layout'+opt)
            run([host, opt, '-fno-pie', '-no-pie', '-Wl,-z,noexecstack',
                 ROOT/'tests/gcc/bitfield-oracle.c', fixture, '-o', binary])
            results.append({'optimization': opt, 'stdout': run([binary]).stdout})
            binary = work/('fibheap'+opt)
            run([host, opt, '-DSIZEOF_INT=4', '-I'+str(source/'include'),
                 ROOT/'tests/gcc/bitfield-fibheap-main.c', obj, '-o', binary])
            assert run([binary]).stdout == output
        report['independent_host_oracle'] = results
        print('PASS: independent O0/O2 ABI/layout/neighbor/value/initializer and original fibheap oracles')
    assert hashes == {p.name: sha(p) for p in names}, 'Compiler changed during proof'
    (work/'report.json').write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
    print(work/'report.json')


if __name__ == '__main__':
    main()
