#!/usr/bin/env python3
"""Check direct-route source inventories and K0 boot wiring without an emulator.

This is a host packaging/static check. It does not prove kernel execution;
use k0/run.sh and k1/run-chain.sh --seed-smoke for the guest proof.
"""
from pathlib import Path
import argparse
import importlib.util
import shlex
import struct
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from tcc_inputs import source_tree, verified_manifest, SOURCE_MANIFEST, prepare


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    import os
    os.chdir(ROOT)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--after", action="store_true", help="also verify all generated prepared-source pins")
    args = parser.parse_args()
    inventory = source_tree()
    pinned = prepare()
    assert len(pinned) == 50
    assert not any(name.startswith("build-out/") for name in inventory)
    if args.after:
        assert len(verified_manifest(SOURCE_MANIFEST)) == 440
    assert not any(p.name in ('pnut.c', 'pnut-exe', 'tcc-pnut', 'tcc-seed') for p in inventory.values())
    for name in ('115-cc-native.fth', '117-cc-native-program.fth',
                 '118-cc-native-init.fth', '119-cc-native-runtime.fth',
                 'tools/tcc-ladder-start.fth', 'tools/tcc-start.fth',
                 'tools/tcc-compile.fth', 'tools/tcc.recipe',
                 'tools/tcc-direct-input.c', 'vendor/pnut/kit/tcc-0.9.27.tar.gz'):
        assert name in inventory, name
    recipe = (ROOT / 'tools/tcc.recipe').read_text()
    runs = [shlex.split(line)[5] for line in recipe.splitlines() if line.startswith('run ')]
    allowed = {'${ROOT}/seed-forth', 'build/tcc-seed', 'build/tcc-boot0',
               'build/tcc-boot1', 'build/tcc-boot2', '${W}/tests/t64',
               '${W}/tests/hello', '${W}/tests/printf', '${W}/tests/test-libc',
               '${W}/tests/rebuilt-features', '${B}/bintools'}
    assert set(runs) <= allowed, set(runs) - allowed
    assert 'tools/amd64.recipe' not in '\n'.join(l for l in recipe.splitlines() if not l.startswith('#'))
    mkdisk = load('k1_mkdisk', ROOT / 'k1/mkdisk.py')
    disk = mkdisk.tree(seed_smoke=True)
    assert sorted(name for name, (path, mode) in disk.items()
                  if path.read_bytes().startswith(b'\x7fELF')) == ['hex0-seed']
    assert sorted(name for name, (path, mode) in disk.items() if mode & 0o111) == ['hex0-seed']
    mkfs = load('k0_mkfs', ROOT / 'k0/mkfs.py')
    with tempfile.TemporaryDirectory() as temp:
        image_path = Path(temp) / 'k0.img'
        mkfs.write(image_path)
        image = image_path.read_bytes()
    def get(addr, count):
        at = addr - mkfs.FSIMG
        return image[at:at + count]
    end = struct.unpack_from('<I', image, mkfs.BASE - mkfs.FSIMG - 112)[0]
    entries = {}
    for at in range(mkfs.ENTS + 24, end, 24):
        name, length, data, size, cap, kind = struct.unpack('<6I', get(at, 24))
        if kind == 1:
            entries[get(name, length).decode()] = (at, get(data, size))
    stdin = struct.unpack_from('<I', image, mkfs.BASE - mkfs.FSIMG + 88)[0]
    assert stdin == entries['tools/tcc-ladder-start.fth'][0]
    assert sorted(name for name, (_, data) in entries.items() if data.startswith(b'\x7fELF')) == ['seed-forth']
    for path in pinned:
        name = str(path.relative_to(ROOT))
        assert entries[name][1] == path.read_bytes(), name
    assert entries['seed-forth'][1] == (ROOT / 'seed-forth').read_bytes()
    assert 'tools/tcc.recipe' in (ROOT / 'k1/mkboot.py').read_text()
    assert '/tools/tcc-ladder-start.fth' in (ROOT / 'k1/k1.recipe').read_text()
    assert '/tools/tcc-ladder-start.fth' in (ROOT / 'k1/seed.recipe').read_text()
    assert 'tools/tcc-ladder-start.fth' in (ROOT / 'tools/run-ladder.sh').read_text()
    assert 'tools/tcc-ladder-start.fth' in (ROOT / 'tools/chain-root.sh').read_text()
    print(f'PASS direct kernel route: {len(inventory)} input files, {len(pinned)} pinned raw inputs, '
          f'{len(runs)} explicit generated compiler/test runs, K0 ELF = seed-forth only, K1 disk ELF = hex0-seed only')


if __name__ == '__main__':
    main()
