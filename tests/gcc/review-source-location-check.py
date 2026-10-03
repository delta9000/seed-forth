#!/usr/bin/env python3
"""Independent physical source-location review, with CPP as a token oracle.

Production preprocessing and executable generation use the seed/Forth chain.
The host compiler only preprocesses independent oracle fixtures. General line
splicing and comments between a macro name and '(' are recorded as preexisting
boundaries, not promoted to supported source-location cases.
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / 'tools/gcc-direct-cc.py'
TOKEN = re.compile(rb'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_][A-Za-z_0-9]*|[0-9]+|[^\s]', re.S)


def c_string(token):
    """Decode C string bytes, including fixed octal escapes in pathnames."""
    body = token[1:-1]
    escapes = {ord('a'): 7, ord('b'): 8, ord('f'): 12, ord('n'): 10,
               ord('r'): 13, ord('t'): 9, ord('v'): 11}
    out = bytearray()
    i = 0
    while i < len(body):
        value = body[i]
        i += 1
        if value == 92:
            value = body[i]
            i += 1
            if 48 <= value <= 55:
                digits = bytes([value])
                while i < len(body) and len(digits) < 3 and 48 <= body[i] <= 55:
                    digits += bytes([body[i]])
                    i += 1
                value = int(digits, 8)
            elif value == ord('x'):
                start = i
                while i < len(body) and body[i] in b'0123456789abcdefABCDEF':
                    i += 1
                value = int(body[start:i], 16)
            else:
                value = escapes.get(value, value)
        out.append(value)
    return bytes(out)


def tokens(data):
    result = []
    for token in TOKEN.findall(data):
        if token.startswith((b'/*', b'//')):
            continue
        result.append(('string', c_string(token)) if token.startswith(b'"') else token)
    return result


CASES = {
    'definition-versus-invocation': '#define L __LINE__\n#define F __FILE__\n\nL F\nL F\n',
    'function-multiline': '#define A(x) __LINE__,x,__LINE__\nA(\n__LINE__\n)\n',
    'nested-function-multiline': '#define A(x) __LINE__,x,__LINE__\n#define B(x) A(x)\nB(\n__LINE__\n)\n',
    'reverse-argument-prescan': '#define A(a,b) a,b,__LINE__\nA(\n__LINE__,\n__LINE__)\n',
    'repeated-raw-argument': '#define A(x) x,x,__LINE__\nA(\n__LINE__\n)\n',
    'paste-builtin-name': '#define C(a,b) a##b\nC(\n__LI,\nNE__)\nC(__FI,LE__)\n',
    'paste-empty': '#define C(a,b) a##b\nC(\n__LINE__,\n)\n',
    'stringify-direct-and-expanded': '#define S(x) #x\n#define X(x) S(x)\nS(__LINE__)\nS(__FILE__)\nX(\n__LINE__\n)\nX(__FILE__)\n',
    'comments-and-blank-lines': '/* one\n two\n three */ __LINE__\n// four\n__LINE__\n\n__LINE__\n',
    'comments-in-arguments': '#define A(x) __LINE__,x,__LINE__\nA(/* first\n second */ __LINE__\n)\n',
    'conditional-locations': '#if __LINE__ == 1\n__LINE__\n#endif\n#if 0\n#elif __LINE__ == 5\n__LINE__\n#endif\n',
    'crlf': '\r\n__LINE__\r\n__LINE__\r\n',
    'continued-definition': '#define A __LINE__ \\\n, __LINE__\nA\n',
    'object-alias-multiline': '#define A(x) __LINE__,x\n#define B A\nB\n(\n__LINE__\n)\n__LINE__\n',
    'nested-object-alias': '#define A(x) __LINE__,x\n#define B C\n#define C A\nB\n(\n__LINE__\n)\n',
    'function-returns-name': '#define A(x) __LINE__,x\n#define B() A\nB()\n(\n__LINE__\n)\n',
    'paste-returns-name': '#define A(x) __LINE__,x\n#define C(a,b) a##b\nC(A,)\n(\n__LINE__\n)\n',
    'function-returns-alias': '#define A(x) __LINE__,x\n#define C A\n#define B() C\nB()\n(\n__LINE__\n)\n',
    'object-returns-function': '#define A(x) __LINE__,x\n#define C() A\n#define B C\nB()\n(\n__LINE__\n)\n',
    'argument-returns-alias': '#define A(x) __LINE__,x\n#define B A\n#define ID(x) x\nID(B)\n(\n__LINE__\n)\n',
    'argument-returns-name': '#define A(x) __LINE__,x\n#define ID(x) x\nID(A)\n(\n__LINE__\n)\n',
    'nested-alias-argument': '#define A(x) __LINE__,x\n#define B A\n#define ID(x) x\nID(B(\n__LINE__\n))\n',
    'object-prefix': '#define A(x) __LINE__,x\n#define B __LINE__,A\nB\n(\n__LINE__\n)\n',
    'undef-redefine': '#if !defined(__LINE__) || !defined(__FILE__)\n#error missing builtins\n#endif\n#undef __LINE__\n#ifdef __LINE__\n#error failed undef\n#endif\n#define __LINE__ 71\n__LINE__\n#undef __FILE__\n#define __FILE__ "replacement"\n__FILE__\n',
    'redefine-as-function': '#undef __LINE__\n#define __LINE__(x) x\n__LINE__(71)\n',
    'skip-line-control': '#if 0\n#line 999 "other.c"\n# 1000 "other.c"\n#endif\n__LINE__ __FILE__\n',
}
BOUNDARIES = {
    'ordinary-line-splicing': '__LINE__ \\\n__LINE__\n',
    'identifier-line-splicing': '__LI\\\nNE__\n',
    'comment-before-call': '#define A(x) __LINE__,x\nA\n/* comment\n*/(\n__LINE__\n)\n',
}


def run(argv, data=None):
    return subprocess.run([str(x) for x in argv], input=data, capture_output=True, timeout=90, cwd=ROOT)


def main():
    paths = sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))
    paths += [ROOT/'010-lib.fth', ROOT/'000-seed.hex0', ROOT/'seed-forth', DRIVER, Path(__file__)]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    work = Path(tempfile.mkdtemp(prefix='review-source-location-', dir=ROOT/'build-out'))
    report = {'source_sha256': hashes, 'cases': [], 'production': 'seed/Forth preprocessing, compiler, runtime and linker',
              'host_oracle': 'cc -E -P token comparison only',
              'reference': 'https://gcc.gnu.org/onlinedocs/cpp/Standard-Predefined-Macros.html'}
    failed = []

    def record(name, passed, **details):
        report['cases'].append({'name': name, 'passed': passed, **details})
        print(('PASS' if passed else 'FAIL') + ': ' + name, flush=True)
        if not passed:
            failed.append(name)

    def compare(name, path, flags=(), boundary=False):
        actual = run([DRIVER, '-E', *flags, path])
        expected = run(['cc', '-E', '-P', *flags, path])
        equal = actual.returncode == expected.returncode == 0 and tokens(actual.stdout) == tokens(expected.stdout)
        details = {'actual': actual.stdout.decode('utf-8', 'backslashreplace'),
                   'expected': expected.stdout.decode('utf-8', 'backslashreplace'),
                   'status': actual.returncode, 'oracle_status': expected.returncode,
                   'source': str(path.relative_to(work))}
        if boundary:
            report.setdefault('preexisting_boundaries', []).append({'name': name, 'matches_host': equal, **details})
            print('BOUNDARY: ' + name, flush=True)
        else:
            record(name, equal, **details)

    for name, source in CASES.items():
        path = work/(name+'.c')
        path.write_bytes(source.encode())
        compare(name, path)
    for name, source in BOUNDARIES.items():
        path = work/(name+'.c')
        path.write_bytes(source.encode())
        compare(name, path, boundary=True)

    (work/'sub').mkdir()
    (work/'sub/deeper').mkdir()
    (work/'sub/a.h').write_text('__LINE__ __FILE__\n#define FROM_A __LINE__,__FILE__\n#include "deeper/b.h"\n__LINE__ __FILE__\n')
    (work/'sub/deeper/b.h').write_text('__LINE__ __FILE__\n#define FROM_B __LINE__,__FILE__\n')
    (work/'sub/c.h').write_text('__LINE__ __FILE__\nFROM_A FROM_B\n')
    path = work/'includes.c'
    path.write_text('__LINE__ __FILE__\n#include "sub/a.h"\n__LINE__ __FILE__\n#include "sub/c.h"\nFROM_A FROM_B\n__LINE__ __FILE__\n')
    compare('nested-and-sibling-includes', path)
    path = work/'command-macro.c'
    path.write_text('LOC FILE\n\nLOC FILE\n#if LOC != 4\n#error command macro shifted source\n#endif\n')
    compare('command-macro-injection', path, ('-DLOC=__LINE__', '-DFILE=__FILE__'))
    for index, spelling in enumerate(('quote"name.c', 'slash\\name.c', 'newline\nname.c', 'tab\tname.c', 'byte\x017name.c', 'unicode-\u00e9.c')):
        path = work/spelling
        path.write_text('__LINE__ __FILE__\n')
        compare('escaped-source-path-'+str(index), path)

    actual = run([DRIVER, '-E', '-'], b'__LINE__ __FILE__\n')
    expected = run(['cc', '-E', '-P', '-'], b'__LINE__ __FILE__\n')
    record('driver-stdin-name', actual.returncode == 0 and tokens(actual.stdout) == tokens(expected.stdout),
           actual=actual.stdout.decode(), expected=expected.stdout.decode())

    modules = [ROOT/'010-lib.fth'] + sorted(p for p in ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')
                                         if p.name not in ('120-cc-main.fth', '140-cc-link.fth'))
    program = b'\n'.join(p.read_bytes() for p in modules)
    for enabled in (False, True):
        config = b'cc-sysv-object-enable\n' if enabled else b''
        command = b': review-location cc-load-stdin cc-preprocess [lit] 1 cc-src-buf cc-src-len @ write drop bye ;\nreview-location\n'
        result = run([ROOT/'seed-forth'], program+b'\n'+config+command+b'__LINE__ __FILE__\n')
        expectation = [b'1', ('string', b'<stdin>')] if enabled else [b'__LINE__', b'__FILE__']
        record('raw-no-path-'+('sysv' if enabled else 'native'), result.returncode == 0 and tokens(result.stdout) == expectation,
               actual=result.stdout.decode(), stderr=result.stderr.decode(), status=result.returncode)

    for index, directive in enumerate(('# 100 "virtual.c"',)):
        path = work/f'line-control-{index}.c'
        path.write_text(directive+'\n__LINE__\n')
        dest = work/f'line-control-{index}.o'
        original = b'previous artifact\n'
        dest.write_bytes(original)
        result = run([DRIVER, '-c', path, '-o', dest])
        record('reject-line-control-'+str(index), result.returncode == 49 and b'error 49' in result.stderr and dest.read_bytes() == original,
               status=result.returncode, stderr=result.stderr.decode())

    header = work/'execute.h'
    header.write_text('static const char header_name[] = __FILE__;\nstatic int header_line = __LINE__;\n#define HEADER_LINE __LINE__\n')
    path = work/'execute.c'
    lines = ['#include <string.h>', '#include "execute.h"', 'static const char source_name[] = __FILE__;',
             '#define AT_LINE __LINE__', 'int main(void) {', '  if (header_line != 2) return 1;',
             '  if (AT_LINE != 7 || HEADER_LINE != 7) return 2;',
             '  if (strcmp(source_name, '+json.dumps(str(path))+')) return 3;',
             '  if (strcmp(header_name, '+json.dumps(str(header))+')) return 4;', '  return 0;', '}']
    path.write_text('\n'.join(lines)+'\n')
    executable = work/'execute'
    result = run([DRIVER, path, '-o', executable])
    execution = run([executable]) if result.returncode == 0 else None
    record('forth-only-source-execution', result.returncode == 0 and execution.returncode == 0,
           compile_status=result.returncode, execution_status=None if execution is None else execution.returncode,
           stderr=result.stderr.decode())

    changed = [name for name, digest in hashes.items() if hashlib.sha256((ROOT/name).read_bytes()).hexdigest() != digest]
    report['input_files_changed_during_review'] = changed
    report['fixture_sha256'] = {str(p.relative_to(work)): hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in sorted(work.rglob('*')) if p.is_file()}
    report['status'] = 'STALE' if changed else 'FAIL' if failed else 'PASS'
    report['failures'] = failed
    destination = work/'report.json'
    destination.write_text(json.dumps(report, indent=2)+'\n')
    print(destination, flush=True)
    raise SystemExit(1 if failed or changed else 0)


if __name__ == '__main__':
    main()
