#!/usr/bin/env python3
"""Create a fresh sparse QEMU RAM backing file inside this checkout's build-out.

No swap, mounts, permissions outside this new file, or system settings change.
QEMU must use memory-backend-file with share=on and prealloc=off. The file is
left behind after QEMU exits; explicitly choose a new pathname for another run.
"""
import argparse
import os
from pathlib import Path
import re
import stat
import sys

ROOT = Path(__file__).resolve().parents[1]


def size_bytes(value):
    match = re.fullmatch(r'([1-9][0-9]*)([KMGTkmgt]?)', value)
    if not match:
        raise ValueError('size must be positive bytes or an integer with K/M/G/T suffix')
    return int(match[1]) * 1024 ** (' KMGT'.index(match[2].upper()) if match[2] else 0)


def create_backing(name, memory, reserve='8G', root=ROOT):
    # QEMU -m interprets a unitless number as MiB, while backend size uses
    # bytes. Require a shared explicit unit before either argument is used.
    if not re.fullmatch(r'[1-9][0-9]*[KMGTkmgt]', memory):
        raise ValueError('file-backed K1_MEM must have an explicit K/M/G/T suffix')
    size, reserve_bytes = size_bytes(memory), size_bytes(reserve)
    if any(ord(c) < 32 or c == ',' for c in name):
        raise ValueError('RAM pathname must not contain control characters or commas')
    given = Path(name)
    if '..' in given.parts:
        raise ValueError('RAM pathname must not contain dot-dot components')
    root = root.resolve()
    path = given if given.is_absolute() else root / given
    base = root / 'build-out'
    try:
        relative = path.relative_to(base)
    except ValueError:
        raise ValueError('RAM file must be inside this checkout\'s build-out directory') from None
    if not relative.parts:
        raise ValueError('RAM file must name a new file, not build-out itself')
    # Every parent must already be a real directory. Never follow a symlink.
    current = base
    for component in ('', *relative.parts[:-1]):
        if component:
            current /= component
        info = current.lstat()
        if not stat.S_ISDIR(info.st_mode):
            raise ValueError(f'RAM parent is not a real directory: {current}')
    try:
        path.lstat()
    except FileNotFoundError:
        pass
    else:
        raise ValueError(f'RAM target already exists: {path}')
    free = os.statvfs(path.parent)
    available = free.f_bavail * free.f_frsize
    if size + reserve_bytes > available:
        raise ValueError(f'RAM backing plus reserve needs {size + reserve_bytes} bytes; '
                         f'only {available} bytes available')
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    owned = os.fstat(fd)
    try:
        os.ftruncate(fd, size)  # sparse sizing only; no page preallocation
    except BaseException:
        os.close(fd)
        now = path.lstat()
        if (now.st_dev, now.st_ino) == (owned.st_dev, owned.st_ino):
            path.unlink()
        raise
    else:
        os.close(fd)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path')
    parser.add_argument('memory', help='guest memory with explicit K/M/G/T suffix')
    parser.add_argument('--reserve', default='8G', help='free-disk headroom beyond the full backing size (default: 8G)')
    args = parser.parse_args()
    try:
        path = create_backing(args.path, args.memory, args.reserve)
    except (OSError, ValueError) as error:
        parser.exit(1, f'k1 RAM backing: {error}\n')
    print(path)


if __name__ == '__main__':
    main()
