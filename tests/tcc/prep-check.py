#!/usr/bin/env python3
"""Run the seed preprocessor directly. No host C preprocessor/compiler is used.

An optional --target KIT check exercises the already pinned/patched TinyCC kit.
--oracle DIR additionally compares tokens with explicitly out-of-chain GCC output
created by the requirement audit; it never feeds that output to the seed.
"""
from pathlib import Path
import argparse
import hashlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TOKEN = re.compile(r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|/\*.*?\*/|//[^\n]*|\s+|[A-Za-z_][A-Za-z_0-9]*|(?:0[xX][0-9a-fA-F]+|\d+)(?:[uUlL]+)?|(?:<<=|>>=|\.\.\.|##|\+\+|--|->|<<|>>|<=|>=|==|!=|&&|\|\||\+=|-=|\*=|/=|%=|&=|\|=|\^=)|.''', re.S)

def tokens(s):
    return [m.group() for m in TOKEN.finditer(s)
            if not m.group().isspace() and not m.group().startswith(('/*', '//'))]

def vocabulary():
    return ''.join(p.read_text() for p in [ROOT / '010-lib.fth'] + sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))
                   if p.name != '120-cc-main.fth')

def run(source, *, direct=True, name=None, includes=(), code=0, vocab=None, cwd=ROOT):
    cfg = 'cc-prep-config-reset\n'
    if direct:
        cfg += 'true cc-prep-direct !\n'
    for i, path in enumerate(includes):
        p = str(path)
        cfg += f'create pp-dir-{i} s, {p}\npp-dir-{i} [lit] {len(p)} cc-prep-add-include\n'
    if name:
        name = str(name)
        cfg += f'create pp-name s, {name}\npp-name [lit] {len(name)} cc-prep-source-name\n'
    cfg += ': pp-test cc-load-stdin cc-preprocess [lit] 1 cc-src-buf cc-src-len @ write drop bye ;\npp-test\n'
    result = subprocess.run([str(ROOT / 'seed-forth')], input=(vocab or vocabulary()) + cfg + source,
                            text=True, capture_output=True, cwd=cwd, timeout=180)
    assert result.returncode == code, (result.returncode, code, result.stderr, result.stdout[:200])
    if not code:
        assert not result.stderr, result.stderr
        assert not re.search(r'^\S+\?$', result.stdout, re.M), result.stdout[:200]
    return result.stdout

def expect(source, expected, **kwargs):
    actual = tokens(run(source, **kwargs))
    want = tokens(expected)
    assert actual == want, (actual, want)

DEFINES = {
    'PNUT_CC': '1', 'PNUT_EXE': '1', 'PNUT_EXE_64': '1', 'PNUT_X86_64': '1',
    'PNUT_X86_64_LINUX': '1', '__linux__': '1', '__x86_64__': '1',
    'BOOTSTRAP': '1', 'HAVE_LONG_LONG': '1', 'TCC_TARGET_X86_64': '1',
    'CONFIG_SYSROOT': '"/"', 'CONFIG_TCC_CRTPREFIX': '"build/boot0-lib"',
    'CONFIG_TCC_ELFINTERP': '"/mes/loader"', 'CONFIG_TCC_SYSINCLUDEPATHS': '"libc64/include"',
    'TCC_LIBGCC': '"build/boot0-lib/libc.a"', 'CONFIG_TCC_LIBTCC1_MES': '0',
    'CONFIG_TCCBOOT': '1', 'CONFIG_TCC_STATIC': '1', 'CONFIG_USE_LIBGCC': '1',
    'TCC_VERSION': '"0.9.27"', 'ONE_SOURCE': '1', 'CONFIG_TCCDIR': '"build/boot0-lib/tcc"',
    '__intptr_t_defined': '1',
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', type=Path)
    parser.add_argument('--oracle', type=Path)
    parser.add_argument('--legacy-pnut', action='store_true', help='verify pinned legacy pnut preprocessing bytes')
    args = parser.parse_args()
    assert (ROOT / 'seed-forth').is_file(), 'Build the seed before running this check'
    expect((ROOT / 'tests/tcc/prep-smoke.c').read_text(),
           (ROOT / 'tests/tcc/prep-smoke.out').read_text())
    multiline = '#define STR(x) #x\nSTR(a\n b)\nafter\n'
    expanded = run(multiline)
    assert expanded.count('\n') == multiline.count('\n'), expanded
    with tempfile.TemporaryDirectory(prefix='sf-prep-') as tmp:
        w = Path(tmp)
        for folder in ('local/sub', 'inc1', 'inc2'):
            (w / folder).mkdir(parents=True)
        (w / 'local/header.h').write_text('#define WHICH 1\n#include "sub/deep.h"\n')
        (w / 'local/sub/deep.h').write_text('#define DEEP 7\n')
        (w / 'inc1/header.h').write_text('#define WHICH 2\n')
        (w / 'inc2/header.h').write_text('#define WHICH 3\n')
        (w / 'inc2/fallback.h').write_text('fallback_found\n')
        (w / 'local/items.h').write_text('DEF(one)\nDEF(two)\n')
        settings = dict(name=w / 'local/main.c', includes=[w / 'inc1', w / 'inc2'])
        expect('#include "header.h"\nWHICH DEEP\n#include <header.h>\nWHICH\n#include "fallback.h"\n',
               '1 7 2 fallback_found', **settings)
        expect('#define DEF(x) first_##x\n#include "items.h"\n#undef DEF\n'
               '#define DEF(x) #x\n#include "items.h"\n', 'first_one first_two "one" "two"', **settings)
        # Angle form must not silently use the including directory or drop a missing header.
        run('#include <items.h>\n', code=30, **settings)
        run('#include "missing.h"\n', code=30, **settings)
        for i in range(7):
            (w / f'inc1/depth{i}.h').write_text(f'#include "depth{i+1}.h"\n' if i < 6 else 'deep_found\n')
        expect('#include <depth0.h>\n', 'deep_found', **settings)
        # #include_next resumes after the directory that held the current file.
        (w / 'inc1/wrap.h').write_text('#include_next <wrap.h>\ninc1_wrap\n')
        (w / 'inc2/wrap.h').write_text('inc2_wrap\n')
        (w / 'inc1/qwrap.h').write_text('#include_next "wrap.h"\nqwrap\n')
        (w / 'local/wrap.h').write_text('#include_next <wrap.h>\nlocal_wrap\n')
        (w / 'inc1/last.h').write_text('#include_next <last.h>\n')
        (w / 'inc2/last.h').write_text('#include_next <last.h>\n')
        expect('#include <wrap.h>\nafter\n', 'inc2_wrap inc1_wrap after', **settings)
        expect('#include <qwrap.h>\n', 'inc2_wrap qwrap', **settings)
        # From a file found without a directory it searches as #include does.
        expect('#include "wrap.h"\n', 'inc2_wrap inc1_wrap local_wrap', **settings)
        expect('#include_next "header.h"\nWHICH\n', '1', **settings)
        run('#include <last.h>\n', code=30, **settings)
        expect('#include_next "header.h"\nkept\n', 'kept', direct=False)
        expect('#include <missing-system-header.h>\nNULL EOF stdin stdout stderr\n',
               '0 0xFFFFFFFFFFFFFFFF 0 1 2', direct=False)
        expect('NULL EOF stdin stdout stderr\n', 'NULL EOF stdin stdout stderr')
    # Legacy output is byte-for-byte unchanged for existing conditional and macro fixtures.
    legacy = {
        'P1-conditionals.c': 'fb22df496fbc1d372a2e32644efc914d552a192979a74f891bd23217c5a55032',
        'P2-fn-macros.c': '86b509b6308b8ca38a4359b56f88c2677c2f9b082a163a0cdbbcf49f208093c2',
    }
    for name, digest in legacy.items():
        out = run((ROOT / 'tests/cc' / name).read_text(), direct=False)
        assert hashlib.sha256(out.encode()).hexdigest() == digest, name
    print('PASS: direct includes, include_next, repeated includes, macro operators, rescanning, and legacy preprocessing')
    if args.legacy_pnut:
        src = '#define target_x86_64_linux 1\n#define ONE_PASS_GENERATOR 1\n'
        src += (ROOT / 'vendor/pnut/pnut.c').read_text()
        out = run(src, direct=False, cwd=ROOT / 'vendor/pnut')
        assert hashlib.sha256(out.encode()).hexdigest() == '5f0a0018af5d620dffa35ee07c16dfe50d43b64212709cce4cb2c375b1579f59'
        print('PASS: pinned legacy pnut preprocessing bytes')
    if args.target:
        kit = args.target.resolve()
        defs = ''.join(f'#define {k} {v}\n' for k, v in DEFINES.items())
        parts = [('libc', kit / 'libc64/libc.c'), ('tcc', kit / 'tcc-0.9.27/tcc.c')]
        for label, path in parts:
            out = run(defs + f'#include "{path}"\n', includes=[kit / 'libc64/include'])
            assert tokens(out), label
            if args.oracle:
                oracle = (args.oracle / f'oracle-seed-{label}.pp.c').read_text()
                assert tokens(out) == tokens(oracle), f'{label}: oracle token mismatch'
            print(f'PASS: pinned {label}: {len(tokens(out))} tokens')
        combined = run(defs + ''.join(f'#include "{p}"\n' for _, p in parts),
                       includes=[kit / 'libc64/include'])
        assert 'int main' in combined
        print(f'PASS: libc-first combined translation unit: {len(combined)} bytes')

if __name__ == '__main__':
    main()
