#!/usr/bin/env python3
"""Run the native lexer stage with Linux Landlock denying host-tool execution.

Requires fresh lexer package directories, seed-cc, and plumbing stage1.
Only execute access is restricted; source inputs can still be read. /tmp is
needed for seed-cc's private copies of the verified seed executable.
"""
from pathlib import Path
import ctypes
import os
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[2]


class Ruleset(ctypes.Structure):
    _fields_ = [('handled_access_fs', ctypes.c_uint64)]


class Beneath(ctypes.Structure):
    _layout_ = 'ms'
    _pack_ = 1
    _fields_ = [('allowed_access', ctypes.c_uint64), ('parent_fd', ctypes.c_int)]


def main():
    if platform.machine() != 'x86_64':
        raise RuntimeError('This seed chain and syscall audit require Linux x86_64')
    os.chdir(ROOT)
    libc = ctypes.CDLL(None, use_errno=True)

    def syscall(number, *args):
        result = libc.syscall(number, *args)
        if result < 0:
            raise OSError(ctypes.get_errno(), os.strerror(ctypes.get_errno()))
        return result

    # LANDLOCK_ACCESS_FS_EXECUTE = 1. No read/write access is constrained.
    ruleset = syscall(444, ctypes.byref(Ruleset(1)), ctypes.sizeof(Ruleset), 0)
    for path in ['seed-forth', 'build-out/seed-cc', 'build-out/plumbing', '/tmp']:
        parent = os.open(path, os.O_PATH | os.O_CLOEXEC)
        syscall(445, ruleset, 1, ctypes.byref(Beneath(1, parent)), 0)
        os.close(parent)
    if libc.prctl(38, 1, 0, 0, 0):  # PR_SET_NO_NEW_PRIVS
        raise OSError(ctypes.get_errno(), os.strerror(ctypes.get_errno()))
    syscall(446, ruleset, 0)
    os.close(ruleset)
    try:
        subprocess.run(['/bin/sh', '-c', 'exit 99'], check=True)
    except PermissionError:
        print('PASS: host shell execution denied; starting native stage', flush=True)
    else:
        raise AssertionError('host shell was executable')
    command = ['build-out/plumbing/bin/kaem', '--verbose', '--strict', '--file', 'plumbing/lexers.kaem']
    os.execv(command[0], command)


if __name__ == '__main__':
    main()
