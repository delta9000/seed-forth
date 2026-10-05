#!/usr/bin/env python3
"""Serial, bounded direct-driver arena tests. Target bytes come from the seed.

The old-cap fixture changes only the driver's ARENA_BYTES value. Fault tests
inject an OS address-space limit into the seed child, never a fallback compiler.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import resource
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CAP = 21 * 1024 * 1024
SEED_SHA = '697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    spec = importlib.util.spec_from_file_location('arena_driver', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    # All compiler children are serial; bound this process and its children.
    soft, hard = resource.getrlimit(resource.RLIMIT_AS)
    limit = min(1024 ** 3, hard) if hard != resource.RLIM_INFINITY else 1024 ** 3
    resource.setrlimit(resource.RLIMIT_AS, (limit, hard))
    driver = load(ROOT / 'tools/gcc-direct-cc.py')
    assert driver.ARENA_BYTES == CAP
    seed = (ROOT / 'seed-forth').read_bytes()
    assert len(seed) == 1772 and sha(seed) == SEED_SHA
    assert b'[lit] 32768 constant cc-arena-cap' in (ROOT / '020-cc-arena.fth').read_bytes()
    assert b'[lit] 8388608 cc-arena-map' in (ROOT / 'tools/tcc-compile.fth').read_bytes()
    (ROOT / 'build-out').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='arena-capacity-', dir=ROOT / 'build-out'))
    records = []
    base = b'\n'.join((ROOT / n).read_bytes() for n in ('010-lib.fth', '020-cc-arena.fth'))

    def forth(name, script, *, status=0, error=b''):
        p = subprocess.run([ROOT / 'seed-forth'], input=base+b'\n'+script,
                           capture_output=True, timeout=10)
        assert (p.returncode, p.stdout, p.stderr) == (status, b'', error), (name, p)
        records.append({'case': name, 'status': p.returncode})

    # Static arena still has its old exact bound. Each mapping is separate.
    for cap in (32768, 8 * 1024 * 1024, 16 * 1024 * 1024, 17 * 1024 * 1024, 20 * 1024 * 1024, CAP):
        setup = b'[lit] 77 cc-src-line !\n'
        if cap != 32768:
            setup += f'[lit] {cap} cc-arena-map\n'.encode()
        setup += b': arena-assert 0= if, [lit] 99 die then, ;\n'
        setup += f'cc-arena-limit @ [lit] {cap} = arena-assert\n'.encode()
        exact = setup + f'[lit] {cap-7} cc-alloc cc-arena-start @ = arena-assert\n'.encode()
        exact += f'cc-arena-ptr @ cc-arena-start @ - [lit] {cap} = arena-assert\n'.encode()
        exact += b'[lit] 0 cc-alloc cc-arena-ptr @ = arena-assert\n'
        forth(f'{cap}-aligned-exact-and-zero', exact+b'bye\n')
        forth(f'{cap}-one-byte-overflow', exact+b'[lit] 1 cc-alloc drop bye\n',
              status=10, error=b'cc: line 77: error 10\n')
    forth('zero-length-mmap-fails', b'[lit] 77 cc-src-line ! [lit] 0 cc-arena-map bye\n',
          status=10, error=b'cc: line 77: error 10\n')

    # The real main/publication path handles both a failed mapping and a late
    # allocation failure. RLIMIT_AS affects only the forked seed executable.
    real_run = subprocess.run
    def low_address_space():
        resource.setrlimit(resource.RLIMIT_AS, (24*1024*1024, 24*1024*1024))
    def fault_run(*args, **kwargs):
        kwargs['preexec_fn'] = low_address_space
        return real_run(*args, **kwargs)
    source = work / 'small.c'
    source.write_text('int main(void) { return 0; }\n')
    for existing in (False, True):
        out = work / ('map-existing.o' if existing else 'map-absent.o')
        sentinel = b'preserve earlier output\n'
        if existing:
            out.write_bytes(sentinel)
        subprocess.run = fault_run
        try:
            try:
                driver.main(['-c', str(source), '-o', str(out)])
            except driver.Failure as failure:
                assert failure.status == 10, failure
            else:
                raise AssertionError('mapping failure did not propagate')
        finally:
            subprocess.run = real_run
        assert out.read_bytes() == sentinel if existing else not out.exists()
        records.append({'case': 'mmap-failure-' + ('existing' if existing else 'absent'), 'status': 10})

    def cc(path, *args, expected=0):
        p = real_run([sys.executable, path, *map(str, args)], capture_output=True, timeout=180)
        assert p.returncode == expected and not p.stdout, (path, args, p)
        if expected:
            assert b'error 10' in p.stderr, p.stderr
        else:
            assert not p.stderr, p.stderr
        return p

    # Repeated compatible prototypes exercise the real parser's arena, keeping
    # the symbol table small and avoiding an unrelated capacity boundary.
    fits = work / 'fits-new.c'
    fits.write_text('int arena_probe(void);\n' * 3000)
    exceeds = work / 'exceeds-new.c'
    exceeds.write_text('int arena_probe(void);\n' * 9000)
    cc(ROOT/'tools/gcc-direct-cc.py', '-c', fits, '-o', work/'fits-new.o')
    records.append({'case': 'real-C-over-8MiB-under-21MiB', 'status': 0,
                    'object_sha256': sha((work/'fits-new.o').read_bytes())})
    for existing in (False, True):
        out = work / ('overflow-existing.o' if existing else 'overflow-absent.o')
        sentinel = b'preserve earlier output\n'
        if existing:
            out.write_bytes(sentinel)
        p = cc(ROOT/'tools/gcc-direct-cc.py', '-c', exceeds, '-o', out, expected=10)
        assert out.read_bytes() == sentinel if existing else not out.exists()
        records.append({'case': 'real-C-overflow-' + ('existing' if existing else 'absent'),
                        'status': 10, 'stderr': p.stderr.decode()})

    # Build the old policy in an isolated source snapshot. All Forth/runtime
    # inputs are identical; a changed driver is itself part of the cache key.
    fixture = work / 'fixture'
    for name in driver.input_names():
        dest = fixture / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, dest)
    path = fixture / 'tools/gcc-direct-cc.py'
    current = path.read_bytes()
    assert current.count(b'ARENA_BYTES = 21 * 1024 * 1024') == 1
    path.write_bytes(current.replace(b'ARENA_BYTES = 21 * 1024 * 1024', b'ARENA_BYTES = 8 * 1024 * 1024'))
    old = load(path)
    old_work = work / 'old-identity'; old_work.mkdir()
    old_identity = old.Toolchain(old_work).identity
    old_fail = work / 'old-fails.o'
    cc(path, '-c', fits, '-o', old_fail, expected=10)
    assert not old_fail.exists()
    cc(path, source, '-o', work/'old-program')
    old_cache = fixture / 'build-out/gcc-direct-cache' / old_identity
    old_manifest = json.loads((old_cache/'manifest.json').read_text())
    assert old_manifest['source_sha256']['tools/gcc-direct-cc.py'] == sha(path.read_bytes())
    path.write_bytes(current)
    new = load(path)
    new_work = work / 'new-identity'; new_work.mkdir()
    new_identity = new.Toolchain(new_work).identity
    assert old_identity != new_identity
    cc(path, source, '-o', work/'new-program')
    new_cache = fixture / 'build-out/gcc-direct-cache' / new_identity
    new_manifest = json.loads((new_cache/'manifest.json').read_text())
    assert new_manifest['source_sha256']['tools/gcc-direct-cc.py'] == sha(current)
    assert old_cache.is_dir() and new_cache.is_dir()
    assert old_manifest['artifact_sha256'] == new_manifest['artifact_sha256']
    before = (work/'old-program').read_bytes(); after = (work/'new-program').read_bytes()
    assert before == after
    p = real_run([work/'new-program'], capture_output=True, timeout=10)
    assert (p.returncode, p.stdout, p.stderr) == (0, b'', b'')
    records.append({'case': 'driver-source-cache-key-and-runtime-byte-preservation',
                    'old_identity': old_identity, 'new_identity': new_identity,
                    'runtime_artifacts': new_manifest['artifact_sha256'],
                    'program_sha256': sha(after)})

    # Arena policy lives in the Python driver. Workspace accessors preserve
    # legacy/native output, including TinyCC's unchanged wrapper.
    # Exercise both shared Forth paths and record emitted byte identities.
    paths = [ROOT/'010-lib.fth'] + sorted(p for p in ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')
                                        if p.name not in ('120-cc-main.fth','140-cc-link.fth'))
    vocab = b'\n'.join(p.read_bytes() for p in paths)
    for label, sample, expected, stdout, setup, word in (
        ('legacy-conditionals', 'tests/cc/P1-conditionals.c',63,b'',b'',b'cc-parse-program'),
        ('legacy-libc','tests/cc/P8-libc-shims.c',42,b'ok\n',b'',b'cc-parse-program'),
        ('native-basics','tests/tcc/native-basics.c',0,b'',
         b'true cc-target-lp64 ! true cc-prep-direct ! [lit] 8388608 cc-arena-map', b'cc-native-program'),
        ('native-many-args','tests/tcc/native-many-args.c',0,b'',
         b'true cc-target-lp64 ! true cc-prep-direct ! [lit] 8388608 cc-arena-map', b'cc-native-program')):
        script = setup+b'\n: preserve cc-load-stdin cc-preprocess cc-out-init cc-globals-init cc-emit-elf-header '+word+b' cc-finalize-globals cc-finalize-elf [lit] 1 cc-out-buf cc-out-pos @ write drop bye ;\npreserve\n'
        p = real_run([ROOT/'seed-forth'], input=vocab+b'\n'+script+(ROOT/sample).read_bytes(),
                     capture_output=True, timeout=30)
        assert p.returncode == 0 and not p.stderr, (label,p)
        # These are the accepted integrated baseline's unchanged emitted bytes.
        pins = {'legacy-conditionals':'91f05862be21595d354e46ad248b69bb8a6770a4bd67e251bea9b11eb4bf4499',
                'legacy-libc':'581c4f676df46fa61b00d33b52f5dee854fa34fd6d769727b87d4eaf71349477',
                'native-basics':'5764f1d9acda186d3dff3502b8aa81820ee59b06ba1cf3bb96196be052d06daa',
                'native-many-args':'e064b2350b76779fb16cc3a19e00ff21f7176fabcb4117999eb84f4c10bd0dc4'}
        assert sha(p.stdout) == pins[label], (label,sha(p.stdout))
        exe=work/label;exe.write_bytes(p.stdout);exe.chmod(0o700)
        result=real_run([exe],capture_output=True,timeout=10)
        assert (result.returncode,result.stdout,result.stderr)==(expected,stdout,b''), result
        records.append({'case': label+'-byte-preservation', 'bytes':len(p.stdout), 'sha256':sha(p.stdout)})
    report={'status':'PASS','arena_bytes':CAP,'seed_bytes':len(seed),'seed_sha256':sha(seed),'cases':records}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: bounded arena, alignment/overflow, mmap failure, atomic publication, cache identity, legacy/native bytes')
    print(work/'report.json')


if __name__ == '__main__':
    main()
