#!/usr/bin/env python3
"""Source-location macros: Forth preprocessing/execution; host CPP is an oracle."""
from pathlib import Path
import ast
import hashlib
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / 'tools/gcc-direct-cc.py'
TOKEN = re.compile(rb'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_][A-Za-z_0-9]*|[0-9]+|[^\s]', re.S)


def tokens(data):
    result = []
    for token in TOKEN.findall(data):
        if token.startswith((b'/*', b'//')):
            continue
        if token.startswith(b'"'):
            result.append(('string', ast.literal_eval(token.decode('ascii'))))
        else:
            result.append(token)
    return result


def command(argv, status=0):
    result = subprocess.run(argv, capture_output=True, timeout=60)
    if result.returncode != status:
        raise AssertionError((argv, result.returncode, result.stdout, result.stderr))
    return result


def main():
    inputs = list(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))
    inputs += [ROOT/'010-lib.fth', ROOT/'tools/gcc-direct-cc.py', Path(__file__)]
    hashes = {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    (ROOT/'build-out').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='source-location-', dir=ROOT/'build-out'))
    (work/'sub').mkdir()
    header = work/'sub/a.h'
    header.write_text('''#define AT_FILE __FILE__
#define AT_LINE __LINE__
#define REPORT(x) __LINE__, x, __FILE__
__LINE__ __FILE__
#include "b.h"
__LINE__ __FILE__
''')
    (work/'sub/b.h').write_text('''__LINE__ __FILE__
#define FROM_HEADER __LINE__, __FILE__
''')
    source = work/'main.c'
    source.write_text('''#if !defined(__LINE__) || !defined(__FILE__)
#error required source-location macros absent
#endif
__LINE__ __FILE__
#include "sub/a.h"
__LINE__ __FILE__
AT_LINE AT_FILE
REPORT(
 AT_LINE
)
FROM_HEADER
#define ID(x) x
ID(
 __LINE__
)
#define QUOTE(x) #x
QUOTE(__LINE__)
#define PASTE(a,b) a ## b
PASTE(__LI,NE__)
/* a multiline
 comment */ __LINE__
#if __LINE__ != 22
#error wrong conditional invocation line
#endif
__LINE__ __FILE__
LOC
''')
    alias = work/'alias.c'
    alias.write_text('#define A(x) __LINE__, x\n#define B A\nB\n(\n __LINE__\n)\n')
    function_alias = work/'function-alias.c'
    function_alias.write_text('#define A(x) __LINE__, x\n#define B() A\nB()\n(\n __LINE__\n)\n')
    cases = [source, alias, function_alias]
    # Quoted, backslashed and control-byte path spellings must remain one C
    # string token, not become directives, separators or unintended escapes.
    for name in ('quote"source.c', 'back\\source.c', 'line\nsource.c', 'tab\tsource.c'):
        path = work/name
        path.write_text('__LINE__ __FILE__\n')
        cases.append(path)
    for path in cases:
        actual = command([DRIVER, '-E', path]).stdout
        expected = command(['cc', '-E', '-P', path]).stdout
        assert tokens(actual) == tokens(expected), (path, actual, expected)
        print('PASS: source tokens match independent CPP for', repr(path.name))
    # A command-line replacement containing a dynamic macro expands at the
    # source use site, after command-macro preprocessing has finished.
    actual = command([DRIVER, '-E', '-DLOC=__LINE__', source]).stdout
    expected = command(['cc','-E','-P','-DLOC=__LINE__',source]).stdout
    assert tokens(actual) == tokens(expected)
    override = work/'override.c'
    override.write_text('''#undef __LINE__
#ifdef __LINE__
#error undef did not remove builtin
#endif
#define __LINE__ 57
__LINE__
#undef __FILE__
__FILE__
''')
    assert tokens(command([DRIVER,'-E',override]).stdout) == [b'57',b'__FILE__']
    # Execution checks both static array materialization and macro invocation
    # in separate included files, without host target code or libc.
    header.write_text('''static const char included_file[] = __FILE__;
static int included_line = __LINE__;
#define HERE __LINE__
''')
    source.write_text('''#include <string.h>
#include "sub/a.h"
static const char original_file[] = __FILE__;
int main(void) {
  if (included_line != 2 || HERE != 5) return 1;
  if (!strstr(included_file, "/sub/a.h")) return 2;
  if (!strstr(original_file, "/main.c")) return 3;
  return 0;
}
''')
    exe = work/'location'
    command([DRIVER,source,'-o',exe])
    command([exe])
    print('PASS: Forth-only static filenames and invocation line execution')
    # C line control is accepted; GNU markers still fail explicitly.
    source.write_text('#line 99 "virtual.c"\n__LINE__ __FILE__\n')
    assert tokens(command([DRIVER,'-E',source]).stdout) == [b'99',('string','virtual.c')]
    for index, text in enumerate(('# 99 "virtual.c"\n__LINE__\n',)):
        source.write_text(text)
        out = work/f'reject-{index}.o'
        out.write_bytes(b'previous artifact\n')
        result = command([DRIVER,'-c',source,'-o',out],status=49)
        assert b'error 49' in result.stderr
        assert out.read_bytes() == b'previous artifact\n'
    source.write_text('#if 0\n#line 99 "virtual.c"\n#endif\n__LINE__\n')
    assert tokens(command([DRIVER,'-E',source]).stdout) == [b'4']
    for name,digest in hashes.items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == digest, 'source changed: '+name
    report={'source_sha256':hashes,'oracle':'host CPP token comparison only','production':'Forth preprocessor/compiler/runtime/linker','line_control':'C #line supported; numeric markers explicitly rejected49; skipped directives ignored','status':'PASS'}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(work/'report.json')


if __name__ == '__main__':
    main()
