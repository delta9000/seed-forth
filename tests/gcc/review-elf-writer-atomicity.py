#!/usr/bin/env python3
"""Minimal fault-injection regression: a failed write must preserve old output.

This test failed against writer SHA256 d687029d099e16af38479ed0f91e7c8f64c96a5999a80813fdc6086ee23c0b9f.
Python creates only the previous-file sentinel and sets a Linux process limit;
the Forth object writer performs the output operation under test.
"""
from pathlib import Path
import os
import resource
import signal
import subprocess
import tempfile

root = Path(os.environ.get('SF_REVIEW_ROOT', Path(__file__).resolve().parents[2])).resolve()
(root / 'build-out').mkdir(exist_ok=True)
out = Path(tempfile.mkdtemp(prefix='review-elf-atomicity-', dir=root / 'build-out'))
dest = out / 'previous.o'
previous = b'previous complete object must survive\n'
dest.write_bytes(previous)
source = '\n'.join((root / p).read_text() for p in
                   ('010-lib.fth', '020-cc-arena.fth', '030-cc-io.fth', '081-cc-object.fth'))
source += f'\ncc-obj-init\ncreate dest s, {dest} [lit] 0 c,\ndest cc-obj-write\n'


def limit():
    resource.setrlimit(resource.RLIMIT_FSIZE, (128, 128))
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)


result = subprocess.run([root / 'seed-forth'], input=source.encode(), capture_output=True,
                        timeout=30, preexec_fn=limit)
assert result.returncode == 248 and b'error 248' in result.stderr, result
assert not result.stdout, result.stdout
assert dest.read_bytes() == previous, (
    f'cc-obj-write lost the old output after a diagnosed EFBIG failure; '
    f'now {dest.stat().st_size} partial bytes: {dest}')
assert sorted(p.name for p in out.iterdir()) == ['previous.o'], list(out.iterdir())
print('review-elf-writer-atomicity: failed object write preserves old output and removes temporary')
