#!/usr/bin/env python3
"""Functional verification of the Forth-built and TinyCC-built helpers.

Host Python provides the test harness/oracle, not compiler inputs. The tools
under test must already have been built by tools/tcc.recipe.
"""
from pathlib import Path
import gzip
import hashlib
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / 'build-out/pnut-amd64/kit'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def check_helpers(kit, label, tools):
    for name, expected in tools.items():
        assert digest((kit / name).read_bytes()) == expected, name
    archive = ROOT / 'vendor/pnut/kit/tcc-0.9.27.tar.gz'
    assert digest(archive.read_bytes()) == 'db0a0bf390c746621b2dc9b8ddf9ff4eeda0c7e3e65e292de5bd8be902eb230d'
    with tempfile.TemporaryDirectory() as temp:
        dest = Path(temp)
        tar = dest / 'tcc.tar'
        subprocess.run([str(kit / 'bintools'), 'ungz', '--file', str(archive),
                        '--output', str(tar)], cwd=dest, check=True, capture_output=True)
        assert tar.read_bytes() == gzip.decompress(archive.read_bytes())
        subprocess.run([str(kit / 'bintools'), 'untar', str(tar)],
                       cwd=dest, check=True, capture_output=True)
        count = 0
        with tarfile.open(archive) as reference:
            for member in reference:
                if member.isfile():
                    assert (dest / member.name).read_bytes() == reference.extractfile(member).read(), member.name
                    count += 1
        patchdir = ROOT / 'patches/amd64/exact'
        op, source, target, before, after, pre, post = (patchdir / 'tcc.manifest').read_text().splitlines()[0].split()
        assert op == 'replace'
        source = dest / source
        assert digest(source.read_bytes()) == pre
        output = dest / 'patched.c'
        subprocess.run([str(kit / 'simple-patch'), 'replace', str(source),
                        str(patchdir / before), str(patchdir / after), str(output)], check=True)
        assert digest(output.read_bytes()) == post
        assert digest(source.read_bytes()) == pre, 'helper changed the input'
        # Existing output is refused without truncating it.
        status = subprocess.run([str(kit / 'simple-patch'), 'copy', str(source), str(output)],
                                capture_output=True).returncode
        assert status != 0 and digest(output.read_bytes()) == post
        print(f'PASS {label} helpers: ungz exact bytes, untar {count} source files, '
              'exact patch pre/post pins, input preservation and existing-output rejection')


def main():
    check_helpers(ROOT / 'build-out/tcc-bootstrap', 'Forth-built raw bootstrap', {
        'bintools': 'd330f693121629b503cc9e6c8c9af1e384df320f80188986070dfa8e5475f5b4',
        'simple-patch': '95782bd922815b1ba9df707a22feebe88e8b723010a4d960348934d00d151fc7'})
    check_helpers(KIT, 'TinyCC-built ladder', {
        'bintools': '26f7128a493101ab13579c8f141b8f5cbd06536c779f001a1f94792ae11d67c0',
        'simple-patch': 'efc7af6660cd232eb024c3ec5831adde6fd8cc56dfe312ddc5597a8f9d050375'})


if __name__ == '__main__':
    main()
