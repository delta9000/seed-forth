#!/usr/bin/env python3
"""Build oyacc 6.6 -> Heirloom lex 070527 -> flex 2.5.11 with Forth.

Usage: python3 gcc-direct/lexers.py INPUTS WORK
INPUTS contains archives/ and recipe-reference/; WORK must not exist.
Host Python, shell, sed and patch orchestrate source preparation only.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import resource
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', type=Path)
    parser.add_argument('work', type=Path)
    args = parser.parse_args()
    # Sequential compilation and a hard per-process ceiling, inherited by children.
    limit = 4 * 1024**3
    soft, hard = resource.getrlimit(resource.RLIMIT_AS)
    resource.setrlimit(resource.RLIMIT_AS, (min(limit, soft) if soft != resource.RLIM_INFINITY else limit, hard))
    inputs, work = args.inputs.resolve(), args.work.resolve()
    work.mkdir()
    environment = dict(os.environ, LC_ALL='C')
    os.environ['LC_ALL'] = 'C'
    steps = []

    def run(command, cwd=work):
        command = list(map(str, command))
        result = subprocess.run(command, cwd=cwd, env=environment, capture_output=True)
        steps.append({'command': command, 'cwd': str(cwd), 'returncode': result.returncode,
                      'stdout': result.stdout.decode(errors='replace'),
                      'stderr': result.stderr.decode(errors='replace')})
        if result.returncode:
            raise RuntimeError(steps[-1])
        return result.stdout.decode().strip()

    preparation = load('lexer_sources', ROOT / 'gcc-direct/prepare-lexer-sources.py')
    source = work / 'sources'
    preparation.prepare(inputs, source)
    cc = [sys.executable, ROOT / 'tools/gcc-direct-cc.py']
    identity = run([*cc, '--print-source-hash'])
    print('Building oyacc', flush=True)
    run([sys.executable, ROOT / 'tests/gcc/oyacc-check.py', source / 'oyacc-6.6',
         '--production-only', '--work', work / 'oyacc'])
    oyacc = work / 'oyacc/production/oyacc'
    driver = load('driver', ROOT / 'tools/gcc-direct-cc.py')
    compiler_work = work / 'compiler'
    compiler_work.mkdir()
    tc = driver.Toolchain(compiler_work)
    if tc.identity != identity:
        raise ValueError('compiler changed before lexer build')
    runtime = tc.runtime_objects()
    start = next(p for p in runtime if p.name == 'start.o')
    archive = tc.runtime_archive([p for p in runtime if p != start], 'libseed.a')

    def compile_units(directory, units, macros=()):
        objects = []
        for unit in units:
            print('Compiling ' + directory.name + '/' + unit, flush=True)
            path = directory / (unit + '.c')
            obj = directory / (unit + '.o')
            tc.compile(path.read_bytes(), path, obj, [directory, tc.runtime / 'include'], macros)
            objects.append(obj)
        return objects

    def link(objects, path):
        tc.link([start, *objects, archive], path)
        path.chmod(0o700)

    heirloom = source / 'heirloom-devtools-070527/lex'
    run([oyacc, 'parser.y'], heirloom)
    (heirloom / 'y.tab.c').rename(heirloom / 'parser.c')
    objects = compile_units(heirloom, 'main sub1 sub2 sub3 header wcio parser getopt lsearch'.split(),
                            ['#define unix 1\n', '#define FORMPATH "' + str(heirloom) + '"\n'])
    link(objects, heirloom / 'lex')
    libraries = compile_units(heirloom, 'allprint libmain reject yyless yywrap'.split())
    libl = tc.runtime_archive(libraries, 'libl.a')
    (heirloom / 'libl.a').write_bytes(libl.read_bytes())

    flex = source / preparation.PINS['archives'][2]['directory']
    probes = {}
    config = ['/* Original configure.in header capabilities tested with production compiler. */\n']
    for macro, headers in [('HAVE_STRING_H', ['string.h']), ('HAVE_MALLOC_H', ['malloc.h']),
                           ('HAVE_SYS_TYPES_H', ['sys/types.h']), ('HAVE_UNISTD_H', ['unistd.h']),
                           ('HAVE_STDBOOL_H', ['stdbool.h']),
                           ('STDC_HEADERS', ['stdlib.h', 'stdarg.h', 'string.h', 'float.h'])]:
        path = compiler_work / (macro + '.c')
        path.write_text(''.join('#include <' + h + '>\n' for h in headers) + 'int main(void){return 0;}\n')
        command = list(map(str, [*cc, path, '-o', compiler_work / macro]))
        result = subprocess.run(command, env=environment, capture_output=True)
        probes[macro] = {'command': command, 'returncode': result.returncode,
                         'stderr': result.stderr.decode(errors='replace')}
        if result.returncode == 0:
            config.append('#define ' + macro + ' 1\n')
    (flex / 'config.h').write_text(''.join(config))
    run([oyacc, '-d', 'parse.y'], flex)
    (flex / 'y.tab.c').rename(flex / 'parse.c')
    (flex / 'y.tab.h').rename(flex / 'parse.h')
    original = (flex / 'scan.lex.l').read_bytes()
    if original.count('Š'.encode()) != 1:
        raise ValueError('expected one U+0160 in attribution comment')
    adapted = original.replace('Š'.encode(), b'S')
    if not adapted.isascii():
        raise ValueError('scanner adaptation must be ASCII')
    (flex / 'scan-ascii.l').write_bytes(adapted)
    adaptation = {'reason': 'C locale wide I/O rejects UTF-8 in source attribution comment',
                  'change': 'One U+0160 letter transliterated S in copyright comment only',
                  'original_sha256': sha(flex / 'scan.lex.l'), 'adapted_sha256': sha(flex / 'scan-ascii.l')}
    run([heirloom / 'lex', 'scan-ascii.l'], flex)
    (flex / 'scan-tmp.c').write_bytes((flex / 'lex.yy.c').read_bytes().replace(b'yylex', b'flexscan'))
    # Preserve the intermediate scanner before flex-tmp overwrites lex.yy.c.
    (flex / 'heirloom-scan.c').write_bytes((flex / 'lex.yy.c').read_bytes())
    units = 'ccl dfa ecs gen main misc nfa parse scan-tmp skel sym tblcmp yylex options scanopt buf'.split()
    macros = ['#define VERSION "2.5.11"\n']
    objects = compile_units(flex, units, macros)
    link([*objects, libl], flex / 'flex-tmp')
    run([flex / 'flex-tmp', 'scan.l'], flex)
    (flex / 'lex.yy.c').rename(flex / 'scan.c')
    objects[units.index('scan-tmp')] = compile_units(flex, ['scan'], macros)[0]
    link([*objects, libl], flex / 'flex')
    run([flex / 'flex', '-V'], flex)
    if identity != run([*cc, '--print-source-hash']):
        raise ValueError('compiler changed during build')
    # Include all executables produced by probes and toolchain, all archives,
    # and every generated C input (including configure probes).
    artifacts = {str(p.relative_to(work)): sha(p) for p in sorted(work.rglob('*'))
                 if p.is_file() and (p.stat().st_mode & 0o111 or p.suffix == '.a')}
    generated = [heirloom / 'parser.c', *[flex / name for name in
                 ['parse.c', 'heirloom-scan.c', 'scan-tmp.c', 'scan.c', 'skel.c']]]
    generated += list((work / 'oyacc/production/generated').glob('*.c'))
    generated += list((work / 'oyacc/probes').glob('*.c')) + list(compiler_work.glob('*.c'))
    artifacts.update({str(p.relative_to(work)): sha(p) for p in generated})
    report = {'compiler_source_identity': identity, 'pins': preparation.PINS,
              'scope': 'oyacc, ordinary Heirloom lex and five-member libl.a, flex 2.5.11; wide/EUC variants untested',
              'tools': {'oyacc': str(oyacc.relative_to(work)), 'lex': str((heirloom / 'lex').relative_to(work)),
                        'flex': str((flex / 'flex').relative_to(work))},
              'sha256': artifacts, 'ascii_comment_adaptation': adaptation,
              'config_probes': probes, 'steps': steps,
              'recipe_sha256': {name: sha(ROOT / name) for name in
                                ['gcc-direct/lexers.py', 'gcc-direct/prepare-lexer-sources.py',
                                 'gcc-direct/lexer-inputs/sources.json', 'tests/gcc/oyacc-check.py']},
              'source_preparation': 'sources/source-preparation.json', 'oyacc_report': 'oyacc/report.json'}
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(work / 'report.json', flush=True)


if __name__ == '__main__':
    main()
