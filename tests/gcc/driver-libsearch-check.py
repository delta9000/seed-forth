#!/usr/bin/env python3
"""Static -L/-l lookup and ordering using Forth-built objects and archives."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CC = ROOT / 'tools/gcc-direct-cc.py'
AR = ROOT / 'tools/gcc-direct-ar.py'


def run(command, work, success=True):
    result = subprocess.run(command, cwd=work, capture_output=True, timeout=60)
    assert (result.returncode == 0) == success, (command, result)
    if success:
        assert not result.stdout and not result.stderr, (command, result)
    return result


def main():
    with tempfile.TemporaryDirectory(prefix='driver-libsearch-') as directory:
        work = Path(directory)
        for name in ('first dir', 'second', 'empty'):
            (work / name).mkdir()
        sources = {
            'main': 'int foo(void); int main(void) { return foo() != EXPECT; }\n',
            'foo': 'int helper(void); int foo(void) { return helper(); }\n',
            'helper': 'int helper(void) { return 7; }\n',
            'other': 'int foo(void) { return 9; }\n',
            'poison': 'int absent(void); int poison(void) { return absent(); }\n',
            'math': '#include <math.h>\nint main(void) { return log(1.0) != 0.0 || exp(0.0) != 1.0; }\n',
            'custom-math': 'double log(double x) { return 17.0; }\n',
            'custom-main': '#include <math.h>\nint main(void) { return log(1.0) != 17.0; }\n',
        }
        for name, text in sources.items():
            (work / (name + '.c')).write_text(text)
            run([CC, '-c', '-DEXPECT=7', name + '.c'], work)
        # The helper appears before its consumer: within-archive rescans are
        # needed, while the poison member must remain unselected.
        run([AR, 'rcs', 'first dir/libfoo.a', 'helper.o', 'poison.o', 'foo.o'], work)
        run([AR, 'rcs', 'second/libfoo.a', 'other.o'], work)
        for arguments in (
            ['-Lfirst dir', '-Lsecond', 'main.o', '-lfoo'],
            ['-L', 'first dir', '-L', 'second', 'main.o', '-l', 'foo'],
            ['main.o', '-lfoo', '-Lfirst dir', '-Lsecond'],
            ['-Lempty', '-Lfirst dir', 'main.o', '-lfoo'],
        ):
            run([CC, *arguments, '-o', 'program'], work)
            run([work / 'program'], work)
        run([CC, '-c', '-DEXPECT=9', 'main.c', '-o', 'nine.o'], work)
        run([CC, '-Lsecond', '-Lfirst dir', 'nine.o', '-lfoo', '-o', 'program'], work)
        run([work / 'program'], work)
        (work / 'preserved').write_bytes(b'existing output')
        run([CC, '-Lfirst dir', '-lfoo', 'main.o', '-o', 'preserved'], work, False)
        assert (work / 'preserved').read_bytes() == b'existing output'
        run([CC, '-Lfirst dir', '-lfoo', 'main.o', '-lfoo', '-o', 'program'], work)
        run([work / 'program'], work)
        for arguments, directories in ((['-lmissing'], ['(none)']),
                                       (['-Lempty', '-Lsecond', '-lmissing'], ['empty', 'second']),
                                       (['-lc'], ['(none)']),
                                       (['-Lempty', '-lc'], ['empty'])):
            failure = run([CC, 'main.o', *arguments, '-o', 'preserved'], work, False)
            assert b'not found; searched directories:' in failure.stderr, failure
            assert (b'-lc' if '-lc' in arguments else b'-lmissing') in failure.stderr
            assert all(name.encode() in failure.stderr for name in directories)
            assert (work / 'preserved').read_bytes() == b'existing output'
        # Neither the current directory nor a shared library is a fallback.
        run([AR, 'rcs', 'libfoo.a', 'other.o'], work)
        (work / 'empty/libfoo.so').write_bytes(b'not a static archive')
        run([CC, 'main.o', '-lfoo', '-o', 'program'], work, False)
        run([CC, '-Lempty', 'main.o', '-lfoo', '-o', 'program'], work, False)
        run([AR, 'rcs', 'first dir/libc.a', 'helper.o', 'foo.o'], work)
        run([CC, '-Lfirst dir', 'main.o', '-lc', '-o', 'program'], work)
        run([work / 'program'], work)
        # Explicit libm wins even if it lacks exp; missing symbols must not
        # cause the builtin archive to supplement that user archive.
        run([AR, 'rcs', 'first dir/libm.a', 'custom-math.o'], work)
        run([CC, '-Lfirst dir', 'custom-main.o', '-l', 'm', '-o', 'program'], work)
        run([work / 'program'], work)
        run([CC, '-Lfirst dir', 'math.o', '-lm', '-o', 'program'], work, False)
        for spelling in (['-lm'], ['-l', 'm']):
            run([CC, '-Lempty', 'math.o', *spelling, '-o', 'program'], work)
            run([work / 'program'], work)
        run([CC, '-Lmissing-dir', 'main.c', '-DEXPECT=7', 'first dir/libfoo.a', '-o', 'program'], work)
        run([work / 'program'], work)
        # Ignored libraries must neither count toward -o's input limit nor
        # trigger lookup or math construction, regardless of mode placement.
        for mode in ('-c', '-E'):
            run([CC, '-lmissing', '-L', 'missing-dir', '-lm', mode,
                 '-DEXPECT=7', 'main.c', '-l', 'c', '-o', 'mode-output'], work)
        for flag in ('-L', '-l'):
            failure = run([CC, 'main.o', flag], work, False)
            assert ('missing argument to ' + flag).encode() in failure.stderr
        print('PASS: static library search order, joined/separate options, input positions,')
        print('      member rescans, explicit-only paths, math precedence/fallback and -c/-E')


if __name__ == '__main__':
    main()
