#!/usr/bin/env python3
"""Verify a supplied TinyCC through the pinned bootstrap continuation.

This is host orchestration, not a seed-only provenance proof. It copies source
bytes and executes only the supplied/generated TinyCC and generated test
programs. No host C compiler, preprocessor, assembler, or linker runs.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shlex
import shutil
import subprocess

OBJECT_PINS = {
    'tcc-boot0.o': '6c69ce160d82eb474d8a04f1227fb9ef414e3450b4af410291ca158a3e7959dc',
    'tcc-boot1.o': '23154c80b00a3ca26122bdb29e4116e5b74510e1bf574ff2ec2f056ddf7cf167',
    'tcc-boot2.o': 'b3730a49338b042d9a3dd3cde1aa4472841296e36f4b09e6e894f405f2648b61',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_copy(source, destination):
    if source.is_symlink() or not source.is_file():
        raise ValueError(f'not a regular source: {source}')
    data = source.read_bytes()
    if data.startswith(b'\x7fELF'):
        raise ValueError(f'ELF passed as source: {source}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    destination.chmod(0o644)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ('repo', 'kit', 'seed', 'dest'):
        parser.add_argument('--' + argument, type=Path, required=True)
    args = parser.parse_args()
    repo, sources, seed, work = (getattr(args, name).resolve()
                                 for name in ('repo', 'kit', 'seed', 'dest'))
    if work.exists():
        parser.error('destination must be new')
    kit = work / 'kit'
    (kit / 'build').mkdir(parents=True)
    for directory in ('tcc-0.9.27', 'libc64'):
        for source in (sources / directory).rglob('*'):
            if source.is_file():
                source_copy(source, kit / source.relative_to(sources))
    for filename in ('kit/libtcc1.c', 'portable_libc/test-libc.c'):
        source_copy(sources / filename, kit / filename)
    shutil.copyfile(seed, kit / 'build/tcc-seed')
    (kit / 'build/tcc-seed').chmod(0o755)

    executions = []

    def run(executable, arguments, output, error, expected=0, timeout=300):
        """Run an explicit generated tool, recording its exact input binary."""
        tool = kit / executable
        digest = sha(tool)
        with (kit / output).open('wb') as stdout, (kit / error).open('wb') as stderr:
            result = subprocess.run([str(tool), *arguments], cwd=kit,
                                    stdin=subprocess.DEVNULL, stdout=stdout,
                                    stderr=stderr, timeout=timeout)
        executions.append({'executable': executable, 'sha256': digest,
                           'arguments': arguments, 'exit': result.returncode,
                           'expected_exit': expected})
        (work / 'executions.json').write_text(json.dumps(executions, indent=2) + '\n')
        if result.returncode != expected:
            raise RuntimeError(f'exit {result.returncode}, expected {expected}: '
                               f'{executable} {arguments}; see {error}')

    # Reuse the existing control continuation verbatim, changing only its
    # supplied compiler pathname. Every generation/artifact pin is retained.
    lines = (repo / 'tools/amd64.recipe').read_text().splitlines()
    start = lines.index('mkdir build/boot0-lib')
    end = next(index for index, line in enumerate(lines)
               if line.startswith('run 0 - ${W}/cc-printf-pnut.log'))
    values = {'ROOT': str(repo), 'W': str(work),
              'TESTS': str(repo / 'tests/pnut/amd64')}
    compilers = {f'build/tcc-{stage}' for stage in ('seed', 'boot0', 'boot1', 'boot2')}
    for line in lines[start:end]:
        for name, value in values.items():
            line = line.replace('${' + name + '}', value)
        line = line.replace('build/tcc-pnut', 'build/tcc-seed')
        words = shlex.split(line)
        if not words:
            continue
        command, *arguments = words
        if command == 'mkdir':
            (kit / arguments[0]).mkdir(parents=True, exist_ok=True)
        elif command == 'text':
            (kit / arguments[0]).write_text(arguments[1])
        elif command == 'same':
            if (kit / arguments[0]).read_bytes() != (kit / arguments[1]).read_bytes():
                raise RuntimeError('fixed-point/output mismatch: ' + line)
        elif command == 'artifact':
            actual = sha(kit / arguments[0])
            if actual != arguments[1]:
                raise RuntimeError(f'artifact mismatch: {arguments[0]}: {actual}')
        elif command == 'contains':
            expected = arguments[1].replace('\\n', '\n').encode()
            if expected not in (kit / arguments[0]).read_bytes():
                raise RuntimeError('expected output absent: ' + line)
        elif command == 'say':
            print(arguments[0], flush=True)
        elif command == 'run':
            status, input_name, output, error, executable, *argv = arguments
            allowed_test = executable.startswith(str(work / 'tests') + '/')
            if executable not in compilers and not allowed_test:
                raise RuntimeError('unexpected executable: ' + executable)
            if input_name != '-':
                raise RuntimeError('unexpected recipe stdin: ' + input_name)
            run(executable, argv, output, error, expected=int(status))
        else:
            raise RuntimeError('unsupported recipe operation: ' + command)

    for filename, expected in OBJECT_PINS.items():
        if sha(kit / 'build' / filename) != expected:
            raise RuntimeError('object differs from independent control: ' + filename)

    # Genuine floating operations are tested only in rebuilt compilers, not
    # the initial Forth compiler's restricted integer-bit-transport dialect.
    for generation in ('boot2', 'boot3'):
        product = str(work / 'tests' / ('rebuilt-features-' + generation))
        run('build/tcc-' + generation,
            ['-static', '-L', 'build/boot2-lib', str(repo / 'tests/tcc/rebuilt-features.c'),
             'build/boot2-lib/libc.o', '-o', product],
            str(work / (generation + '-features-cc.log')),
            str(work / (generation + '-features-cc.err')))
        run(product, [], str(work / (generation + '-features.log')),
            str(work / (generation + '-features.err')), timeout=30)
    print('PASS rebuilt float/double/long-double arithmetic, bitfields, VLA and local enum')
    print(f'PASS downstream: {len(executions)} generated-tool/test executions; '
          'all existing generation pins and executable/object fixed points. '
          'This alone does not establish seed provenance.')


if __name__ == '__main__':
    main()
