#!/usr/bin/env python3
"""Prepare pinned lexer sources offline, writing only to a fresh destination.

Derived from the 2026-10-03 evidence prepare-inputs.py and
prepare-flex-source.py; live-bootstrap reference identity is in sources.json.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import tarfile

BASE = Path(__file__).resolve().parent
PINS = json.loads((BASE / 'lexer-inputs/sources.json').read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(inputs, destination):
    # Check everything before creating the destination. Inputs remain read-only.
    for pin in PINS['archives']:
        path = inputs / 'archives' / pin['archive']
        if sha(path) != pin['sha256']:
            raise ValueError('archive pin mismatch: ' + str(path))
    for name, digest in PINS['reference_sha256'].items():
        if sha(inputs / 'recipe-reference' / name) != digest:
            raise ValueError('reference pin mismatch: ' + name)
    destination.mkdir()
    inventory = {}
    for pin in PINS['archives']:
        with tarfile.open(inputs / 'archives' / pin['archive']) as archive:
            seen = set()
            for member in archive.getmembers():
                relative = Path(member.name)
                if (relative.is_absolute() or '..' in relative.parts or
                        not relative.parts or relative.parts[0] != pin['directory'] or
                        not (member.isfile() or member.isdir()) or relative in seen):
                    raise ValueError('unsafe archive member: ' + member.name)
                seen.add(relative)
                if member.isdir():
                    continue
                data = archive.extractfile(member).read()
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                inventory[str(relative)] = hashlib.sha256(data).hexdigest()
    flex = destination / PINS['archives'][2]['directory']
    reference = inputs / 'recipe-reference/steps/flex-2.5.11'
    patches = []
    for name in ['scan_l.patch', 'yyin.patch']:
        command = ['patch', '--batch', '--fuzz=0', '-p1', '-i', str(reference / 'patches' / name)]
        result = subprocess.run(command, cwd=flex, capture_output=True, text=True, check=True)
        patches.append({'command': command, 'stdout': result.stdout, 'stderr': result.stderr})
    shutil.copyfile(reference / 'files/scan.lex.l', flex / 'scan.lex.l')
    # Never allow a shipped parser/scanner to become a bootstrap input.
    for name in ['parse.c', 'parse.h', 'scan.c', 'skel.c']:
        (flex / name).unlink(missing_ok=True)
    command = ['/bin/sh', str(flex / 'mkskel.sh'), str(flex / 'flex.skl')]
    result = subprocess.run(command, capture_output=True, check=True)
    expected = b'/* File created from flex.skl via mkskel.sh */\n\n#include "flexdef.h"\n\nconst char *skel[] = {\n'
    for line in (flex / 'flex.skl').read_bytes().splitlines():
        expected += b'  "' + line.replace(b'\\', b'\\\\').replace(b'"', b'\\"') + b'",\n'
    expected += b'  0\n};\n'
    if result.stdout != expected:
        raise ValueError('independent skeleton byte-escaping check failed')
    (flex / 'skel.c').write_bytes(result.stdout)
    report = {'pins': PINS, 'original_files_sha256': inventory, 'patches': patches,
              'skeleton_command': command, 'skeleton_independent_check': 'PASS',
              'prepared_sha256': {name: sha(flex / name) for name in
                                  ['scan.l', 'flexdef.h', 'scan.lex.l', 'skel.c']}}
    (destination / 'source-preparation.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    prepare(args.inputs.resolve(), args.destination.resolve())


if __name__ == '__main__':
    main()
