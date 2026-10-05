#!/usr/bin/env python3
"""Bounded live-symbol table tests; the unchanged seed performs every check.

The old/new source comparison uses only the previous literal capacity. No host
compiler, assembler, linker or preprocessor participates in target generation.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PATHS = [ROOT / '010-lib.fth'] + sorted(
    p for p in ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')
    if p.name not in ('120-cc-main.fth', '140-cc-link.fth'))
OLD_HASH = '8a9e30febd1e922d953395beca49aec0b59204dde36cd948891b626181d2cb8d'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def main():
    current = (ROOT / '070-cc-sym.fth').read_bytes()
    assert current.count(b'[lit] 8192 constant cc-sym-cap') == 1
    old = current.replace(b'[lit] 8192 constant cc-sym-cap',
                          b'[lit] 4096 constant cc-sym-cap')
    assert sha(old) == OLD_HASH, 'preservation baseline source changed'
    vocab = [b'\n'.join(old if previous and p.name == '070-cc-sym.fth'
                        else p.read_bytes() for p in PATHS)
             for previous in (True, False)]
    (ROOT/'build-out').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='symbol-capacity-', dir=ROOT/'build-out'))
    records = []
    def run(name, script, *, previous=False, source=b'', status=0, error=b''):
        p = subprocess.run([ROOT/'seed-forth'], cwd=ROOT,
                           input=vocab[0 if previous else 1]+b'\n'+script+source,
                           capture_output=True, timeout=90)
        assert p.returncode == status, (name, p.returncode, p.stderr, p.stdout[:150])
        assert p.stderr == error, (name, p.stderr)
        records.append({'case':name, 'status':p.returncode, 'bytes':len(p.stdout),
                        'sha256':sha(p.stdout)})
        return p.stdout

    # Exercise every row and every parallel column, including the extended half.
    # The separate SysV signature column is also sized by cc-sym-cap.
    boundary = b'''
: sym-assert 0= if, [lit] 99 die then, ;
create sym-name [lit] 120 c,
variable sym-i
[lit] 0 cc-sym-count ! [lit] 0 cc-scope-depth ! [lit] 77 cc-src-line !
: sym-add sym-name [lit] 1 sk-local ty-int [lit] 0 ty-make sym-i @ cc-sym-add ;
: sym-zero ( id -- )
  dup cc-sym-extra cell[] @ 0= sym-assert
  dup cc-sym-extra2 cell[] @ 0= sym-assert
  dup cc-sym-desc cell[] @ 0= sym-assert
  dup cc-sym-inner cell[] @ 0= sym-assert
  cc-sym-qualified cell[] @ 0= sym-assert ;
: sym-row ( id -- )
  dup cc-sym-name-addr cell[] @ sym-name = sym-assert
  dup cc-sym-name-len cell[] @ [lit] 1 = sym-assert
  dup cc-sym-kind-of sk-local = sym-assert
  dup cc-sym-type-of ty-int [lit] 0 ty-make = sym-assert
  dup cc-sym-val-of sym-i @ = sym-assert sym-zero ;
: sym-fill
  [lit] 0 sym-i !
  begin, sym-i @ cc-sym-cap < while,
    sym-add dup sym-i @ = sym-assert sym-row
    sym-i @ [lit] 17 + sym-i @ cc-sysv-signatures cell[] !
    [lit] 1 sym-i +!
  repeat, ;
sym-fill
cc-sym-count @ cc-sym-cap = sym-assert
sym-name [lit] 1 cc-sym-find cc-sym-cap 1- = sym-assert
[lit] 0 cc-sysv-signatures cell[] @ [lit] 17 = sym-assert
cc-sym-cap 1- cc-sysv-signatures cell[] @ cc-sym-cap [lit] 16 + = sym-assert
here [lit] 20971520 < sym-assert
'''
    assert run('all-8192-rows-and-cap-derived-signatures', boundary+b'bye\n') == b''
    run('one-past-8192-fails-60', boundary+b'sym-add drop bye\n',
        status=60, error=b'cc: line 77: error 60\n')
    reuse = b'''
cc-sym-cap 1- cc-sym-count ! cc-scope-push
cc-sym-cap 1- sym-i ! sym-add drop
[lit] 41 sym-i @ cc-sym-extra cell[] !
[lit] 42 sym-i @ cc-sym-extra2 cell[] !
[lit] 43 sym-i @ cc-sym-desc cell[] !
[lit] 44 sym-i @ cc-sym-inner cell[] !
[lit] 45 sym-i @ cc-sym-qualified cell[] !
cc-scope-pop
cc-sym-count @ cc-sym-cap 1- = sym-assert
sym-add dup sym-i @ = sym-assert sym-row
cc-sym-count @ cc-sym-cap = sym-assert bye
'''
    assert run('last-row-scope-reuse-clears-all-five-aux-columns', boundary+reuse) == b''
    # Confirm the unchanged all-layer loader also fits, including the linker.
    for index, text in enumerate(vocab):
        p = subprocess.run([ROOT/'seed-forth'], input=text+b'\n'+
                           (ROOT/'140-cc-link.fth').read_bytes()+
                           b'\nhere cc-err-dec bye\n', capture_output=True, timeout=10)
        assert p.returncode == 0 and not p.stdout
        end = int(p.stderr)
        assert end < 0x1400000
        records.append({'case':'dictionary-end-old' if index == 0 else 'dictionary-end-new',
                        'address':end,'mapping_end':0x1400000,'headroom':0x1400000-end})

    def preserve(name, source, setup=b'', word=b'cc-parse-program', expected=0, stdout=b''):
        script = setup+b'\n: preserve cc-load-stdin cc-preprocess cc-out-init cc-globals-init '+\
            b'cc-emit-elf-header '+word+\
            b' cc-finalize-globals cc-finalize-elf [lit] 1 cc-out-buf cc-out-pos @ write drop bye ;\npreserve\n'
        before = run(name+'-old',script,previous=True,source=source)
        after = run(name+'-new',script,source=source)
        assert before == after, name
        output=work/name; output.write_bytes(after); output.chmod(0o700)
        p=subprocess.run([output],cwd=ROOT,capture_output=True,timeout=10)
        assert (p.returncode,p.stdout,p.stderr) == (expected,stdout,b''), (name, p.returncode, p.stdout, p.stderr)
    for name, expected, stdout in (('P1-conditionals.c',63,b''),('P2-fn-macros.c',30,b''),
                                   ('P3-casts.c',74,b''),('P8-libc-shims.c',42,b'ok\n')):
        preserve('legacy-'+name,(ROOT/'tests/cc'/name).read_bytes(),expected=expected,stdout=stdout)
    for name in ('basics','layout','stack-call','literals','many-args','switch-goto'):
        preserve('native-'+name,(ROOT/f'tests/tcc/native-{name}.c').read_bytes(),
                 b'true cc-target-lp64 ! true cc-prep-direct ! [lit] 8388608 cc-arena-map',
                 b'cc-native-program')
    # Full C object path: 8191 anonymous enumerators plus one function use
    # exactly 8192 rows. One extra enumerator must preserve an existing output
    # and must not publish a new output when the subsequent function overflows.
    for count in (8191, 8192):
        source = work/f'enum-{count}.c'
        source.write_text('enum {\n'+''.join(f'E{i}={i},\n' for i in range(count))+
                          '};\nint top(void) { return E8190; }\n')
        out = work/f'enum-{count}.o'
        variants = ('at-limit',) if count == 8191 else ('existing-output','absent-output')
        for variant in variants:
            sentinel = b'previous output must survive\n'
            if variant == 'existing-output':
                out.write_bytes(sentinel)
            elif out.exists():
                out.unlink()
            p = subprocess.run([sys.executable,ROOT/'tools/gcc-direct-cc.py','-c',source,'-o',out],
                               cwd=ROOT,capture_output=True,timeout=90)
            if count == 8191:
                assert p.returncode == 0 and not p.stdout and not p.stderr, (p.returncode,p.stderr)
                data=out.read_bytes();assert data[:4] == b'\x7fELF'
                records.append({'case':'c-object-at-8192-live-symbols','sha256':sha(data),'bytes':len(data)})
            else:
                assert p.returncode == 60 and b'error 60' in p.stderr and not p.stdout, (p.returncode,p.stderr)
                assert out.read_bytes() == sentinel if variant == 'existing-output' else not out.exists()
                records.append({'case':'c-object-one-past-'+variant,'status':60,'stderr':p.stderr.decode()})
    seed=(ROOT/'seed-forth').read_bytes()
    report={'status':'PASS','old_symbol_source_sha256':sha(old),
            'current_symbol_source_sha256':sha(current),'seed_bytes':len(seed),
            'seed_sha256':sha(seed),'cases':records}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: 8192 symbols, one-past rejection, scope reuse, qualification reset, dictionary bounds, legacy/native byte identity')
    print(work/'report.json')
if __name__ == '__main__':
    main()
