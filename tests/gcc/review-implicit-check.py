#!/usr/bin/env python3
"""Independent C90 implicit-call review; every target artifact is Forth-built.

Host GCC -std=gnu89 builds separate positive oracles, never target inputs.
Fault-injection controls use in-memory Forth bindings, without editing sources.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / 'tests/gcc'
MODES = ('mapped', 'object')
SENTINEL = b'previous valid artifact\n'
REJECTIONS = {
    'unknown-value': (93, 'int main(void){return absent;}'),
    'unknown-address': (93, 'int main(void){int (*p)(int);p=&absent;return 0;}'),
    'unknown-pointer-value': (93, 'int main(void){int (*p)(int);p=absent;return 0;}'),
    'unknown-parenthesized-call': (93, 'int main(void){return (absent)(1);}'),
    'tag-is-not-value': (93, 'struct absent{int x;};int main(void){return absent;}'),
    'expired-function-value': (93, 'int a(void){return absent(1);}int main(void){int (*p)(int);p=absent;return 0;}'),
    'expired-block-value': (93, 'int main(void){{absent(1);}return absent;}'),
    'ordinary-local-shadow': (230, 'int absent(int);int main(void){int absent=0;return absent(1);}'),
    'ordinary-typedef-shadow': (230, 'int absent(int);int main(void){typedef int absent;return absent(1);}'),
    'ordinary-enumerator-shadow': (230, 'int absent(int);int main(void){enum E{absent=1};return absent(1);}'),
    'persistent-return-conflict': (237, 'int a(void){{return absent(1);}}int b(int reused){return reused;}long absent(int x){return x;}int main(void){return 0;}'),
    'persistent-char-prototype-conflict': (237, 'int a(void){return absent(1);}int b(int reused){return reused;}int absent(char);int main(void){return 0;}'),
    'persistent-char-definition-conflict': (237, 'int a(void){return absent(1);}int absent(char x){return x;}int main(void){return 0;}'),
    'persistent-variadic-conflict': (237, 'int a(void){return absent(1);}int absent(int,...);int main(void){return 0;}'),
    'persistent-object-conflict': (237, 'int a(void){return absent(1);}int b(int reused){return reused;}int absent;int main(void){return 0;}'),
    'persistent-extern-object-conflict': (237, 'int a(void){return absent(1);}extern int absent;int main(void){return 0;}'),
    'persistent-static-linkage-conflict': (237, 'int a(void){return absent(1);}static int absent(int x){return x;}int main(void){return 0;}'),
    'persistent-static-prototype-conflict': (237, 'int a(void){return absent(1);}static int absent(int);int main(void){return 0;}'),
    'later-prototype-count': (235, 'int a(void){return absent(1);}int absent(int);int main(void){return absent();}'),
}
POSITIVES = {
    'later-compatible-long-prototype': 'int a(void){return target(41L);}int target(long);int b(void){return target(42L);}int target(long x){return x-40;}int main(void){return a()!=1||b()!=2;}',
    'later-compatible-void-prototype': 'int a(void){return target();}int target(void);int target(void){return 7;}int main(void){return a()!=7;}',
    'earlier-static-linkage': 'static int target(int);int a(void){return target(9);}static int target(int x){return x;}int main(void){return a()!=9;}',
    'unevaluated-implicit-call': 'int main(void){return sizeof(absent())!=sizeof(int);}',
    'call-after-local-shadow-expires': 'int main(void){{int target;target=7;}return target(8)!=8;}int target(int x){return x;}',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def checked(command, expected=0, **kwargs):
    result = subprocess.run(command, capture_output=True, timeout=60, **kwargs)
    assert expected is None or result.returncode == expected, (command, result.returncode,
                                                               expected, result.stdout,
                                                               result.stderr)
    return result


def symbols(path):
    data = path.read_bytes()
    elf = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    assert elf[0][:7] == b'\x7fELF\x02\x01\x01' and elf[1] == 1
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, elf[6]+i*elf[11])
                for i in range(elf[12])]
    table = next(section for section in sections if section[1] == 2)
    string_section = sections[table[6]]
    strings = data[string_section[4]:string_section[4]+string_section[5]]
    result = []
    for offset in range(table[4], table[4]+table[5], table[9]):
        symbol = struct.unpack_from('<IBBHQQ', data, offset)
        name = strings[symbol[0]:].split(b'\0', 1)[0].decode()
        result.append((name, symbol[1] >> 4, symbol[1] & 15, symbol[3]))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    gcc = shutil.which('gcc')
    if not gcc:
        raise SystemExit('GCC is required only for the separate gnu89 oracle')
    paths = [ROOT / 'seed-forth', ROOT / '010-lib.fth']
    paths += [path for path in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))
              if path.name not in ('120-cc-main.fth', '140-cc-link.fth')]
    paths += [ROOT / '140-cc-link.fth', Path(__file__),
              TESTS / 'review-implicit-caller.c', TESTS / 'review-implicit-provider.c']
    source_bytes = {path: path.read_bytes() for path in paths}
    hashes = {str(path.relative_to(ROOT)): sha(data) for path, data in source_bytes.items()}
    compiler = b'\n'.join(source_bytes[path] for path in paths[1:]
                           if path.suffix == '.fth' and path.name != '140-cc-link.fth')
    base = b'\n'.join(source_bytes[ROOT / name] for name in
                       ('010-lib.fth', '020-cc-arena.fth', '030-cc-io.fth'))
    outputs = {}
    mutation_outcomes = {}
    counts = {'positive_executions': 0, 'rejection_publication_checks': 0,
              'native_checks': 0, 'mutation_controls': 0}

    with tempfile.TemporaryDirectory(prefix='review-implicit.') as directory:
        work = Path(directory)

        def forth(program, expected=0):
            result = checked([ROOT / 'seed-forth'], expected, input=program)
            assert not result.stdout, result.stdout
            return result

        def compile_source(source, output, mode, expected=0, overlay=''):
            source = source if isinstance(source, bytes) else source.encode()
            enable = {'mapped': 'cc-sysv-enable', 'object': 'cc-sysv-object-enable',
                      'native': 'true cc-target-lp64 ! true cc-prep-direct !'}[mode]
            action = ('cc-sysv-object-program review-output cc-obj-write' if mode == 'object'
                      else 'cc-emit-elf-header ' + ('cc-native-program' if mode == 'native'
                           else 'cc-sysv-program') +
                      ' cc-finalize-globals cc-finalize-elf review-output cc-write-output')
            driver = f'''\n{enable}\n{overlay}\n[lit] 8388608 cc-arena-map
create review-output s, {output} [lit] 0 c,
: review-main cc-load-stdin cc-preprocess cc-out-init cc-globals-init
  {action} bye ;
review-main
'''
            result = forth(compiler + driver.encode() + source + b'\n', expected)
            if result.returncode:
                assert re.search(rb'cc: line \d+: error ' + str(result.returncode).encode() + rb'\b',
                                 result.stderr), result.stderr
            else:
                assert not result.stderr, result.stderr
                if mode != 'object':
                    output.chmod(0o755)
            return result

        start = work / 'start.o'
        start_driver = f'''
create review-path s, {start} [lit] 0 c,
create review-start s, _start
create review-main s, main
variable review-main-id
cc-obj-init
[lit] 232 cc-obj-byte [lit] 0 cc-obj-4le
[lit] 137 cc-obj-byte [lit] 199 cc-obj-byte
[lit] 184 cc-obj-byte [lit] 60 cc-obj-4le
[lit] 15 cc-obj-byte [lit] 5 cc-obj-byte
review-start [lit] 6 cc-obj-global cc-obj-func cc-obj-default
cc-obj-text [lit] 0 [lit] 14 cc-obj-symbol drop
review-main [lit] 4 cc-obj-global cc-obj-func cc-obj-default
cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol review-main-id !
cc-obj-text [lit] 1 cc-obj-plt32 review-main-id @ [lit] 0 [lit] 4 - cc-obj-reloc
review-path cc-obj-write
'''
        forth(base + b'\n' + source_bytes[ROOT / '081-cc-object.fth'] + start_driver.encode())

        def link(objects, output, expected=0):
            driver = '\nlnk-init\n'
            for index, obj in enumerate(objects):
                driver += f'create review-in-{index} s, {obj} [lit] 0 c,\n'
                driver += f'review-in-{index} lnk-add-object\n'
            driver += 'create review-entry s, _start\nreview-entry [lit] 6 lnk-entry\n'
            driver += f'create review-output s, {output} [lit] 0 c,\nreview-output lnk-link\n'
            result = forth(base + b'\n' + source_bytes[ROOT / '140-cc-link.fth'] + driver.encode(), expected)
            if not expected:
                assert not result.stderr, result.stderr
            return result

        def execute(output):
            result = checked([output])
            assert not result.stdout and not result.stderr, result
            counts['positive_executions'] += 1

        caller = source_bytes[TESTS / 'review-implicit-caller.c']
        provider = source_bytes[TESTS / 'review-implicit-provider.c']
        combined = caller + b'\n' + provider
        mapped = work / 'combined'
        compile_source(combined, mapped, 'mapped')
        execute(mapped)
        objects = []
        for name, source in (('caller', caller), ('provider', provider), ('combined', combined)):
            output = work / (name + '.o')
            compile_source(source, output, 'object')
            outputs[name + '.o'] = sha(output.read_bytes())
            objects.append(output)
        unresolved_names = {'review_external', 'review_negative', 'review_eight',
                            'review_oldstyle', 'review_implicit_tag'}
        entries = symbols(objects[0])
        for name in unresolved_names:
            assert [item for item in entries if item[0] == name] == [(name, 1, 2, 0)], entries
        for name, order in (('forward', [start, *objects[:2]]),
                            ('reverse', [objects[1], objects[0], start]),
                            ('combined', [start, objects[2]])):
            output = work / ('linked-' + name)
            link(order, output)
            execute(output)
            outputs['linked-' + name] = sha(output.read_bytes())
        print('PASS: scoped call/address fixups, repeated names, eight arguments and tags; mapped and Forth-linked objects', flush=True)

        for name, source in POSITIVES.items():
            mapped = work / name
            compile_source(source, mapped, 'mapped')
            execute(mapped)
            obj = work / (name + '.o')
            compile_source(source, obj, 'object')
            linked = work / (name + '-linked')
            link([start, obj], linked)
            execute(linked)
            print('PASS:', name, 'mapped and Forth-linked', flush=True)

        # Separate GCC-built programs corroborate only defined positive C90 behavior.
        oracle_sources = {'combined': combined, **POSITIVES}
        for name, source in oracle_sources.items():
            source = source if isinstance(source, bytes) else source.encode()
            path = work / ('oracle-' + name + '.c')
            path.write_bytes(source + b'\n')
            for optimization in ('-O0', '-O2'):
                output = work / ('oracle-' + name + optimization[1:])
                checked([gcc, '-std=gnu89', '-fno-builtin', optimization, path, '-o', output])
                execute(output)
        print('PASS: separate GCC gnu89 -O0/-O2 positive oracles', flush=True)

        for name, (code, source) in REJECTIONS.items():
            for mode in MODES:
                output = work / (name + '-' + mode)
                for existing in (False, True):
                    if existing:
                        output.write_bytes(SENTINEL)
                    compile_source(source, output, mode, code)
                    assert output.read_bytes() == SENTINEL if existing else not output.exists(), (name, mode)
                    counts['rejection_publication_checks'] += 1
            print('PASS:', name, 'rejects', code, 'with absent/preserved output in both modes', flush=True)

        unresolved_source = 'struct absent{int x;};int a(void){return absent(1);}int b(void){return absent(2);}int main(void){return a()+b();}'
        unresolved = work / 'unresolved.o'
        compile_source(unresolved_source, unresolved, 'object')
        assert [entry for entry in symbols(unresolved) if entry[0] == 'absent'] == [('absent', 1, 2, 0)]
        for existing in (False, True):
            output = work / 'unresolved-mapped'
            linked = work / 'unresolved-linked'
            if existing:
                output.write_bytes(SENTINEL)
                linked.write_bytes(SENTINEL)
            compile_source(unresolved_source, output, 'mapped', 206)
            link([start, unresolved], linked, 253)
            for path in (output, linked):
                assert path.read_bytes() == SENTINEL if existing else not path.exists(), path
                counts['rejection_publication_checks'] += 1
        print('PASS: tag/implicit undefined symbol survives ET_REL; mapped206 and linker253 preserve output', flush=True)

        native_bad = work / 'native-implicit'
        compile_source('int main(void){return absent();}', native_bad, 'native', 93)
        assert not native_bad.exists()
        native_good = work / 'native-known'
        compile_source('int known(int);int main(void){return known(9)!=9;}int known(int x){return x;}', native_good, 'native')
        execute(native_good)
        counts['native_checks'] = 2

        # Remove the new lookup hook to reproduce the original undeclared-call failure.
        mutant = work / 'mutant-disabled'
        compile_source(combined, mutant, 'mapped', 93,
                       "' cc-native-unknown-ident-default is cc-native-unknown-ident-fwd")
        assert not mutant.exists()
        mutation_outcomes['disabled-implicit-hook'] = {'compile_exit': 93}
        counts['mutation_controls'] += 1
        # Drop persistent call/address cells; a block-pop now loses or misattributes fixups.
        # A correct runtime result would mean the positive fixture failed to detect that bug.
        for label, overlay in (
                ('lost-call-scope', "' cc-sym-call-fixups-default is cc-sym-call-fixups"),
                ('lost-address-scope', "' cc-sym-addr-fixups-default is cc-sym-addr-fixups")):
            output = work / label
            result = compile_source(combined, output, 'mapped', expected=None, overlay=overlay)
            outcome = {'compile_exit': result.returncode}
            if result.returncode:
                # Only an ordinary unresolved-function error is an expected early kill.
                assert result.returncode == 206, (label, result.returncode)
                assert not output.exists(), label
            else:
                try:
                    result = subprocess.run([output], capture_output=True, timeout=2)
                except subprocess.TimeoutExpired:
                    outcome['runtime_timeout'] = True
                else:
                    outcome['runtime_exit'] = result.returncode
                    assert result.returncode != 0, (label, 'survived runtime oracle')
            mutation_outcomes[label] = outcome
            counts['mutation_controls'] += 1
        print('PASS: original undeclared-call failure and two lost-scope fixup mutants detected; native behavior unchanged', flush=True)

    assert all(path.read_bytes() == data for path, data in source_bytes.items()), 'review inputs changed during run; rerun stable sources'
    report = {'source_sha256': hashes, 'target_sha256': outputs, **counts,
              'mutation_outcomes': mutation_outcomes,
              'positive_c90_cases': len(POSITIVES) + 1,
              'rejection_cases': len(REJECTIONS),
              'target_artifacts_built_only_with_forth': True,
              'host_gcc_only_separate_gnu89_oracles': True}
    if args.json:
        args.json.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps(report, sort_keys=True))


if __name__ == '__main__':
    main()
