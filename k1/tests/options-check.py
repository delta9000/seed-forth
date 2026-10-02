#!/usr/bin/env python3
"""Host-only regression checks for guest JOBS and safe sparse RAM-file setup."""
from pathlib import Path
import argparse
import importlib.util
import os
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'k1' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def reject(call):
    try:
        call()
    except (OSError, ValueError, argparse.ArgumentTypeError):
        return
    raise AssertionError('unsafe input was accepted')


def main():
    disk, ram = load('mkdisk'), load('mkram')
    assert disk.guest_recipe() == (ROOT / 'k1/k1.recipe').read_bytes()
    assert disk.guest_recipe(True, 1) == (ROOT / 'k1/seed.recipe').read_bytes()
    recipe = disk.guest_recipe(False, 1).decode()
    assert recipe.count('/env JOBS=1 ') == 3
    for value in ('0', '-1', '257', '1;echo bad', '1 2', '1.5', '１', ''):
        reject(lambda value=value: disk.positive_jobs(value))
    assert ram.size_bytes('3G') == 3 * 1024 ** 3
    for value in ('0', '-1G', '1.5G', '2GB', '1G,share=off'):
        reject(lambda value=value: ram.size_bytes(value))
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        base = root / 'build-out'
        base.mkdir()
        target = ram.create_backing('build-out/ram', '4M', '1M', root)
        assert target.stat().st_size == 4 * 1024 ** 2
        assert target.stat().st_mode & 0o777 == 0o600
        assert target.stat().st_blocks * 512 < target.stat().st_size
        reject(lambda: ram.create_backing('build-out/ram', '4M', '1M', root))
        reject(lambda: ram.create_backing('outside', '4M', '1M', root))
        for numeric in ('16', '4096', '17179869184'):
            reject(lambda numeric=numeric: ram.create_backing('build-out/unitless', numeric, '1M', root))
        assert not (base / 'unitless').exists()
        reject(lambda: ram.create_backing('build-out/../outside', '4M', '1M', root))
        reject(lambda: ram.create_backing('build-out/ram,share=off', '4M', '1M', root))
        (base / 'link').symlink_to(root)
        reject(lambda: ram.create_backing('build-out/link/ram', '4M', '1M', root))
        (base / 'dangling').symlink_to(root / 'absent')
        reject(lambda: ram.create_backing('build-out/dangling', '4M', '1M', root))
        (base / 'directory').mkdir()
        reject(lambda: ram.create_backing('build-out/directory', '4M', '1M', root))
        with patch.object(ram.os, 'statvfs', return_value=SimpleNamespace(f_bavail=1, f_frsize=4096)):
            reject(lambda: ram.create_backing('build-out/no-space', '4M', '1M', root))
        assert not (base / 'no-space').exists()
        (base / 'ram').unlink()
        with patch.object(ram.os, 'ftruncate', side_effect=OSError('test failure')):
            reject(lambda: ram.create_backing('build-out/failure', '4M', '1M', root))
        assert not (base / 'failure').exists()
    print('PASS K1 options: default recipes unchanged, explicit guest JOBS, sparse private file, '
          'overwrite/path/symlink/space guards and failed-creation cleanup')


if __name__ == '__main__':
    main()
