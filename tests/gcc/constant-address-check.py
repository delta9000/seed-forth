#!/usr/bin/env python3
"""Address-constant grammar, relocation and null-base offset oracle."""
from pathlib import Path
import argparse
import hashlib
import json
import runpy
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASE = "c805ff20443e5bbf607979c3156c1328005053d09a78fcf4db3f4c8faf898cae"
DECLS = """struct Leaf { char c; long n; };
union Payload { long n; struct Leaf leaf; };
struct Record { char tag; struct Leaf items[3]; union Payload u; long *p; };
"""
OFFSETS = [
    ('(unsigned long)&(((struct Leaf*)0)->n)', 8),
    ('(unsigned long)&(((*(struct Leaf*)0)).n)', 8),
    ('(unsigned long)&((((struct Leaf*)0))->n)', 8),
    ('(unsigned long)&(((struct Record*)0)->items[2].n)', 48),
    ('(unsigned long)&(((struct Record*)0)->u.leaf.n)', 64),
    ('(unsigned long)&((struct Leaf*)0)[2].n', 40),
    ('(unsigned long)&((long*)0)[3]', 24),
    ('(unsigned long)&((char*)0)[3]', 3),
    ('(unsigned long)&((struct Leaf*)128)->n', 136),
    ('(unsigned long)&((struct Leaf*)(1 ? 0 : 1/0))->n', 8),
    ('(unsigned long)(&((struct Leaf*)0)->n + 2)', 24),
    ('(unsigned long)&((struct Leaf*)0)->n + 2', 10),
    ('(unsigned long)&((struct Record*)0)->items[sizeof(int)-2].n', 48),
    ('(unsigned long)&((struct Record*)0)->items[(unsigned long)&((struct Leaf*)0)->n/4].n', 48),
    ('(unsigned long)&*(long*)0', 0),
    ('1 ? 77UL : (unsigned long)&((struct Record*)0)->items[1/0].n', 77),
    ('0 ? (unsigned long)&((struct Record*)0)->items[1/0].n : 77UL', 77),
    ('(unsigned long)&((struct Record*)0)->items[1 ? 2 : 1/0].n', 48),
    ('(unsigned long)&((struct Leaf*)0)->n + sizeof(int[3])', 20),
    ('(unsigned long)&((struct Record*)0)->items', 8),
]
REJECT = {
    '&((struct Leaf*)0)': 240,
    '&((long)0)': 240,
    '&((struct Leaf*)0).n': 240,
    '&((struct Leaf**)0)->n': 240,
    '&((long*)0)->n': 240,
    '&((void*)0)[0]': 240,
    '&((struct Leaf*)0)->absent': 90,
    '&((struct Record*)0)->items[-1].n': 240,
    '&((struct Record*)0)->items[4].n': 240,
    '&((struct Record*)0)->p[1]': 240,
    '&(struct Leaf*)0->n': 240,
    '&*(long)0': 240,
    '&((struct Leaf*)0)->n++': 240,
    '&((struct Leaf*)0)->n = 1': 240,
    '&((struct Record*)0)->items[1/0].n': 124,
}


def checked(argv, **kw):
    result = subprocess.run([str(a) for a in argv], capture_output=True, timeout=120, **kw)
    assert result.returncode == 0, (argv, result.returncode, result.stdout, result.stderr)
    return result


def object_values(path, names):
    """Extract initialized symbol bytes from ELF64, independent of layout."""
    data = path.read_bytes()
    assert data[:5] == b'\x7fELF\x02'
    offset = struct.unpack_from('<Q', data, 40)[0]
    entry_size, count = struct.unpack_from('<HH', data, 58)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i*entry_size)
                for i in range(count)]
    result = {}
    for section in sections:
        if section[1] != 2:
            continue
        string_section = sections[section[6]]
        strings = data[string_section[4]:string_section[4]+string_section[5]]
        for pos in range(section[4], section[4]+section[5], section[9]):
            name, info, other, index, value, size = struct.unpack_from('<IBBHQQ', data, pos)
            name = strings[name:strings.find(b'\0', name)].decode()
            if name not in names:
                continue
            target = sections[index]
            result[name] = data[target[4]+value:target[4]+value+size]
    assert set(result) == set(names), result.keys()
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rtl-invocation', type=Path)
    ap.add_argument('--baseline-root', type=Path)
    args = ap.parse_args()
    gcc = shutil.which('gcc')
    assert gcc, 'GCC is required as the independent test oracle'
    (ROOT/'build-out').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='constant-address-', dir=ROOT/'build-out'))
    helper = runpy.run_path(str(ROOT/'tests/gcc/constant-check.py'))
    expressions = [e for e, _ in OFFSETS]
    source = DECLS + ';\n'.join(expressions) + ';\n'
    result = helper['seed'](source, len(expressions), api='cc-parse-integer-const cc-om-address-frame @ if, [lit] 243 cc-die then,', setup='cc-sysv-object-enable cc-obj-init', declarations=3)
    assert result.returncode == 0, (result.returncode, result.stderr)
    actual = list(struct.iter_unpack('<QQ', result.stdout))
    assert actual == [(v, 12 << 16) for _, v in OFFSETS], actual
    for expression, code in REJECT.items():
        result = helper['seed'](DECLS + expression + ';', 1,
                                setup='cc-sysv-object-enable cc-obj-init', declarations=3)
        assert result.returncode == code, (expression, result.returncode, result.stderr)
    print(f'PASS: {len(OFFSETS)} address values/types, nested pool watermarks; {len(REJECT)} rejections')
    header = '#include <stddef.h>\n' + DECLS
    (work/'layout.h').write_text(header)
    producer = '#include "layout.h"\nunsigned long offsets[] = {\n'
    producer += ',\n'.join(expressions) + '\n};\n'
    producer += '''struct Record record;
struct Leaf records[4];
long *symbolic[] = { &record.items[2].n, &((record).items[1].n),
 &((struct Record*)&record)->u.leaf.n,
 &((struct Leaf*)records)[2].n,
 &((struct Record*)&record)->items[(unsigned long)&((struct Leaf*)0)->n/4].n,
 &record.items[0].n + 2, &*(&record.items[1].n) };
unsigned long offset_macro = offsetof(struct Record, items[2].n);
unsigned long offset_enum_size = sizeof(char[1 + offsetof(struct Leaf, n)]);
int function(void) {return 23;}
int (*function_address)(void) = &(function);
'''
    (work/'producer.c').write_text(producer)
    consumer = '#include "layout.h"\nextern unsigned long offsets[], offset_macro, offset_enum_size;\n'
    consumer += 'extern struct Record record; extern struct Leaf records[4]; extern long *symbolic[];\n'
    consumer += 'extern int (*function_address)(void);\nint main(void) {\n'
    for i, (_, value) in enumerate(OFFSETS):
        consumer += f'if(offsets[{i}] != {value}UL) return {i+1};\n'
    consumer += '''if(offset_macro != __builtin_offsetof(struct Record, items[2].n)) return 40;
if(offset_enum_size != 1 + __builtin_offsetof(struct Leaf, n)) return 41;
if(symbolic[0] != &record.items[2].n || symbolic[1] != &record.items[1].n) return 42;
if(symbolic[2] != &record.u.leaf.n || symbolic[3] != &records[2].n) return 43;
if(symbolic[4] != &record.items[2].n || symbolic[5] != &record.items[0].n + 2) return 44;
if(symbolic[6] != &record.items[1].n || function_address() != 23) return 45;
return 0; }
'''
    (work/'consumer.c').write_text(consumer)
    checked([ROOT/'tools/gcc-direct-cc.py', '-c', work/'producer.c', '-o', work/'seed.o'])
    checked([gcc, '-std=c90', '-w', '-c', work/'producer.c', '-o', work/'host.o'])
    for name in ('seed', 'host'):
        checked([gcc, '-no-pie', work/'consumer.c', work/(name+'.o'), '-o', work/name])
        checked([work/name])
    bad = {
      'bitfield': 'struct X {unsigned x:3;}; unsigned long a=(unsigned long)&((struct X*)0)->x;',
      'pointer-load': 'struct X {long x;}; struct X *p; long *a=&(p->x);',
      'automatic': 'long *f(void) {long x; static long *p=&(x); return p;}',
      'narrow-function': 'int f(void); int *a=(int*)(int)f;',
      'increment': DECLS + 'long *a=&((struct Leaf*)0)->n++;',
      'assignment': DECLS + 'long *a=&((struct Leaf*)0)->n=1;',
      'call': 'long f(void); long *a=&(f());',
      'cast-precedence': DECLS + 'long *a=&(struct Leaf*)0->n;',
    }
    for name, content in bad.items():
        path = work/(name+'.c'); path.write_text(content)
        output = work/(name+'.o'); output.write_bytes(b'preserve output')
        r = subprocess.run([ROOT/'tools/gcc-direct-cc.py', '-c', path, '-o', output], capture_output=True)
        assert r.returncode != 0 and output.read_bytes() == b'preserve output', (name, r.returncode)
    print('PASS: GCC C90 object/execution oracle; symbolic relocation targets/addends; output publication guards')
    report = {'base_source_hash': BASE, 'source_hash': checked([ROOT/'tools/gcc-direct-cc.py', '--print-source-hash']).stdout.decode().strip(),
              'positive_cases': len(OFFSETS), 'parser_rejections': len(REJECT), 'object_rejections': len(bad), 'oracle': 'PASS'}
    if args.rtl_invocation:
        invocation = json.loads(args.rtl_invocation.read_text()); argv = invocation['arguments'][:]
        for item in invocation['inputs']:
            assert hashlib.sha256(Path(item['path']).read_bytes()).hexdigest() == item['sha256'], item
        out = work/'rtl.o'; argv[argv.index('-o')+1] = str(out)
        checked([ROOT/'tools/gcc-direct-cc.py', *argv], cwd=invocation['cwd'])
        assert out.read_bytes()[:4] == b'\x7fELF'
        report['original_rtl'] = {'invocation': str(args.rtl_invocation.resolve()), 'input': invocation['inputs'][0], 'object_sha256': hashlib.sha256(out.read_bytes()).hexdigest()}
        expanded = work/'rtl.i'
        prep = argv[:]; prep[prep.index('-c')] = '-E'; prep[prep.index('-o')+1] = str(expanded)
        checked([ROOT/'tools/gcc-direct-cc.py', *prep], cwd=invocation['cwd'])
        host = work/'rtl-host.o'
        checked([gcc, '-w', '-c', '-x', 'c', expanded, '-o', host])
        names = ['rtx_size', 'rtx_length', 'rtx_class']
        actual = object_values(out, names); expected = object_values(host, names)
        assert actual == expected, 'original rtl initializer bytes differ from host GCC'
        report['original_rtl']['host_initializer_oracle'] = {
            name: {'bytes': len(actual[name]), 'sha256': hashlib.sha256(actual[name]).hexdigest()}
            for name in names}
        print('PASS: untouched GCC rtl.c original rule; rtx_size/length/class bytes match host GCC')
    if args.baseline_root:
        preservation(helper, args.baseline_root.resolve(), report)
    (work/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(work/'report.json')


def preservation(helper, baseline, report):
    paths = [ROOT/'010-lib.fth'] + [p for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')) if p.name not in ('120-cc-main.fth','140-cc-link.fth')]
    vocab = [b'\n'.join((baseline/p.name if old and p.name in ('123-cc-object-program.fth','125-cc-consteval.fth') else p).read_bytes() for p in paths) for old in (True,False)]
    records=[]
    for native, names in [(False,['P1-conditionals','P2-fn-macros','P3-casts','P8-libc-shims']), (True,['basics','layout','stack-call','literals','many-args','switch-goto'])]:
        for name in names:
            source=(ROOT/('tests/tcc/native-'+name+'.c' if native else 'tests/cc/'+name+'.c')).read_bytes()
            setup=b'true cc-target-lp64 ! true cc-prep-direct ! [lit] 8388608 cc-arena-map\n' if native else b''
            parser=b'cc-native-program' if native else b'cc-parse-program'
            script=setup+b': preservation cc-load-stdin cc-preprocess cc-out-init cc-globals-init cc-emit-elf-header '+parser+b' cc-finalize-globals cc-finalize-elf [lit] 1 cc-out-buf cc-out-pos @ write drop bye ;\npreservation\n'
            answers=[checked([ROOT/'seed-forth'],input=v+b'\n'+script+source,cwd=ROOT).stdout for v in vocab]
            assert answers[0] == answers[1], name
            records.append({'case':name,'native':native,'bytes':len(answers[0]),'sha256':hashlib.sha256(answers[0]).hexdigest()})
    report['legacy_native_byte_preservation']=records
    print('PASS: 10 legacy/native outputs remain byte-identical')


if __name__ == '__main__':
    main()
