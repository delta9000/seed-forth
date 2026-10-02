#!/usr/bin/env python3
"""Host-only raw-input verification and image inventory for the direct route.

Host preparation copies only raw pinned archives, libc and tool sources.
Unpacking and exact patching happen inside tools/tcc.recipe with Forth-built
helpers. Image writers share this inventory, including new Forth layers.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE_MANIFEST = ROOT / 'tools/tcc-source-inputs.sha256'
RAW_SOURCE_MANIFEST = ROOT / 'tools/tcc-raw-inputs.sha256'
TOOL_SOURCE_MANIFEST = ROOT / 'tools/tcc-bintools-inputs.sha256'


def source_bytes(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'not a regular source file: {path}')
    data = path.read_bytes()
    if data.startswith(b'\x7fELF'):
        raise ValueError(f'executable in source inventory: {path}')
    return data


def verified_manifest(manifest):
    result = []
    for line in manifest.read_text().splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        digest, name = line.split()
        rel = PurePosixPath(name)
        if rel.is_absolute() or '..' in rel.parts:
            raise ValueError(f'unsafe source path: {name}')
        path = ROOT / name
        if hashlib.sha256(source_bytes(path)).hexdigest() != digest:
            raise ValueError(f'source hash mismatch: {name}')
        result.append(path)
    return result


def prepare():
    """Verify raw inputs; do not extract, patch, or generate any source file."""
    return verified_manifest(RAW_SOURCE_MANIFEST) + verified_manifest(TOOL_SOURCE_MANIFEST)


def source_tree():
    """Return repository-relative path -> regular source Path for root images.

    Only the caller adds hex0-seed/seed-forth or an explicitly requested K1
    test executable. The pnut compiler sources and pnut-produced executables
    are not part of this default direct-route inventory.
    """
    files = [ROOT / '000-seed.hex0'] + list(ROOT.glob('[0-9][0-9][0-9]-*.fth'))
    for directory in ('tools', 'ladder', 'patches/amd64/exact', 'patches/gcc64',
                      'patches/ladder', 'patches/tcc-ladder', 'tests/pnut/amd64', 'tests/tcc',
                      'tests/gcc64', 'gcc64', 'k1'):
        files += [p for p in (ROOT / directory).rglob('*')
                  if p.is_file() and '__pycache__' not in p.parts
                  and p.suffix not in ('.pyc', '.pyo')]
    files += prepare()
    result = {}
    for path in files:
        source_bytes(path)
        result[str(path.relative_to(ROOT))] = path
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list', action='store_true', help='list full source-only image inventory')
    args = parser.parse_args()
    if args.list:
        print('\n'.join(sorted(source_tree())))
    else:
        files = prepare()
        print(f'direct-tcc: verified {len(files)} pinned raw archive/libc/tool inputs')
