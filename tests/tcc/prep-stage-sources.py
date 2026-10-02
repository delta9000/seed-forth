#!/usr/bin/env python3
"""Stage pinned TinyCC/bootstrap-libc sources without running pnut.

This is explicitly a host-side source-preparation helper: Python decompresses
and copies source bytes and applies the repository's exact hashed patches.
It does not compile, preprocess, link, or create any executable. The seed
compiler must process direct-input.c itself, with kit/libc64/include as an
explicit include directory and the input file's pathname supplied to prep.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import importlib.util
import json
import tarfile
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
PATCHES = ROOT / 'patches/amd64/exact'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verified(path, expected):
    data = path.read_bytes()
    actual = sha(data)
    if actual != expected:
        raise ValueError(f'hash mismatch: {path}: {actual} != {expected}')
    return data


def pins(manifest):
    return dict((path, digest) for digest, path in
                (line.split() for line in manifest.read_text().splitlines() if line.strip()))


def below(base, rel):
    path = PurePosixPath(rel)
    if path.is_absolute() or '..' in path.parts:
        raise ValueError(f'unsafe relative source pathname: {rel}')
    return base.joinpath(*path.parts)


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def patch(kit, manifest):
    for line in manifest.read_text().splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        op, source, dest, before, after, source_sha, result_sha = line.split()
        if op == 'copy':
            result = verified(below(PATCHES, source), source_sha)
        elif op == 'replace':
            original = verified(below(kit, source), source_sha)
            old = below(PATCHES, before).read_bytes()
            new = below(PATCHES, after).read_bytes()
            if not old or original.count(old) != 1:
                raise ValueError(f'patch must have exactly one nonempty match: {line}')
            result = original.replace(old, new, 1)
        else:
            raise ValueError(f'unsupported source operation: {op}')
        if sha(result) != result_sha:
            raise ValueError(f'patched source hash mismatch: {dest}')
        write(below(kit, dest), result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='new source-only directory, must not exist')
    parser.add_argument('--compare', type=Path, help='optional existing pnut control source tree')
    args = parser.parse_args()
    kit = args.output.resolve()
    if kit.exists():
        raise ValueError(f'refusing to overwrite existing source tree: {kit}')
    input_pins = pins(ROOT / 'tools/amd64-inputs.sha256')
    libc_pins = pins(ROOT / 'tools/amd64-libc.sha256')
    tarpath = 'vendor/pnut/kit/tcc-0.9.27.tar.gz'
    verified(ROOT / tarpath, input_pins[tarpath])
    kit.mkdir(parents=True)
    with tarfile.open(ROOT / tarpath, 'r:gz') as archive:
        for member in archive:
            dst = below(kit, member.name)
            if not PurePosixPath(member.name).parts or PurePosixPath(member.name).parts[0] != 'tcc-0.9.27':
                raise ValueError(f'unexpected tar member: {member.name}')
            if member.isdir():
                dst.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                with archive.extractfile(member) as source:
                    write(dst, source.read())
            else:
                raise ValueError(f'non-regular source archive member: {member.name}')
    verified(kit / 'tcc-0.9.27/lib/va_list.c',
             '3204e28b30bc7cbd4ea9520377e69a6feef11e110081bd05d1136fdcbf50c6f1')
    for name, digest in libc_pins.items():
        rel = Path(name).relative_to('vendor/pnut/portable_libc')
        write(kit / 'libc64' / rel, verified(ROOT / name, digest))
    for name, dest in [('vendor/pnut/kit/config.h', 'tcc-0.9.27/config.h'),
                       ('vendor/pnut/kit/libtcc1.c', 'kit/libtcc1.c'),
                       ('vendor/pnut/portable_libc/test-libc.c', 'portable_libc/test-libc.c')]:
        write(kit / dest, verified(ROOT / name, input_pins[name]))
    for name in ('kit.manifest', 'tcc.manifest', 'libc.manifest'):
        patch(kit, PATCHES / name)
    source_files = sorted(p for directory in ('tcc-0.9.27', 'libc64', 'kit', 'portable_libc')
                          for p in (kit / directory).rglob('*') if p.is_file())
    if args.compare:
        control = args.compare.resolve()
        for path in source_files:
            reference = control / path.relative_to(kit)
            if path.read_bytes() != reference.read_bytes():
                raise ValueError(f'control source mismatch: {reference}')
        print(f'PASS: {len(source_files)} source files byte-identical to the control tree')
    spec = importlib.util.spec_from_file_location('prep_check', ROOT / 'tests/tcc/prep-check.py')
    profile = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(profile)
    definitions = ''.join(f'#define {name} {value}\n' for name, value in profile.DEFINES.items())
    write(kit / 'direct-input.c', (definitions + '#include "libc64/libc.c"\n'
                                 '#include "tcc-0.9.27/tcc.c"\n').encode())
    manifest = {str(p.relative_to(kit)): sha(p.read_bytes()) for p in source_files}
    manifest['direct-input.c'] = sha((kit / 'direct-input.c').read_bytes())
    write(kit / 'source-manifest.json', (json.dumps(manifest, indent=2) + '\n').encode())
    print(f'Staged source only: {kit}')
    print(f'Input: {kit / "direct-input.c"}')
    print(f'Explicit include directory: {kit / "libc64/include"}')


if __name__ == '__main__':
    main()
