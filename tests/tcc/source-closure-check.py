#!/usr/bin/env python3
"""Verify direct TinyCC's source-only executable closure (host verification).

Source preparation is a separate, explicit host-side step. This verifier does
not preprocess or compile C. It verifies a reviewed manifest, stages text files
and the original seed into a fresh root, then observes Linux exec syscalls from
outside that root. Only seed-forth executes inside the compilation boundary.
PASS covers the direct seed build, not TinyCC self-hosting/runtime correctness.
Missing user namespaces, chroot, or syscall auditing is SKIP (exit 77), never PASS.

Example, after prep-stage-sources.py has created build-out/tcc-sources:
  python3 tests/tcc/source-closure-check.py --sources build-out/tcc-sources \
      --write-manifest build-out/tcc-closure-inputs.json
  # Review that explicit hash manifest, then run:
  python3 tests/tcc/source-closure-check.py --sources build-out/tcc-sources \
      --manifest build-out/tcc-closure-inputs.json --dest build-out/tcc-isolated \
      --pin EXPECTED_SHA256

The manifest records source bytes, not permission to substitute arbitrary
executables. The seed has an independent, fixed original hash. No host compiler,
pnut binary, object/archive, interpreter, shell, /bin, or /usr is staged.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SEED_SHA256 = '697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e'
FORMAT = 'direct-tcc-source-closure-v1'
SOURCE_PREFIX = 'build-out/tcc-sources/'
START = 'tools/tcc-start.fth'
PRODUCT = 'build-out/tcc-seed'
FORTH_FILES = (
    '010-lib.fth', '020-cc-arena.fth', '030-cc-io.fth', '040-cc-prep.fth',
    '050-cc-lex.fth', '060-cc-types.fth', '070-cc-sym.fth', '080-cc-elf.fth',
    '090-cc-emit.fth', '100-cc-expr.fth', '110-cc-decl.fth', '112-cc-stmt.fth',
    '114-cc-func.fth', '115-cc-native.fth', '116-cc-prog.fth',
    '117-cc-native-program.fth', '118-cc-native-init.fth',
    '119-cc-native-runtime.fth', START, 'tools/tcc-compile.fth',
)
HEX = re.compile(r'[0-9a-f]{64}\Z')
EXEC = re.compile(r'^(?:\[pid\s+)?(\d+)\]?\s+execve\("([^"\\]*)",.*\)\s+=\s+0$')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def relative(name):
    if not isinstance(name, str) or not name or '\\' in name:
        raise ValueError(f'invalid relative path: {name!r}')
    parts = name.split('/')
    if any(p in ('', '.', '..') for p in parts) or PurePosixPath(name).is_absolute():
        raise ValueError(f'invalid relative path: {name!r}')
    return Path(*parts)


def regular(base, name):
    rel = relative(name)
    path = base
    for part in rel.parts:
        path = path / part
        if path.is_symlink():
            raise ValueError(f'symlink in source path: {path}')
    if not path.is_file():
        raise ValueError(f'not a regular source file: {path}')
    return path.read_bytes()


def source_text(data, name):
    # Every pinned prepared input is text. Reject binary blobs even when their
    # execute bits or suffix have been disguised. Shell source stays inert text.
    if b'\0' in data or data.startswith((b'\x7fELF', b'MZ', b'!<arch>\n',
                                       b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf')):
        raise ValueError(f'binary in source-only inputs: {name}')
    if Path(name).name == 'pnut.c':
        raise ValueError(f'pnut compiler source in direct-route inputs: {name}')


def mapping_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key}')
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(), object_pairs_hook=mapping_pairs)


def source_inputs(repo, sources):
    prepared = read_json(sources / 'source-manifest.json')
    if not isinstance(prepared, dict) or not prepared:
        raise ValueError('prepared source manifest must be a nonempty object')
    expected = set(prepared) | {'source-manifest.json'}
    actual = set()
    for path in sources.rglob('*'):
        if path.is_symlink():
            raise ValueError(f'symlink in prepared source tree: {path}')
        if path.is_file():
            actual.add(path.relative_to(sources).as_posix())
        elif not path.is_dir():
            raise ValueError(f'nonregular entry in source tree: {path}')
    if actual != expected:
        raise ValueError(f'unmanifested/missing prepared sources: {sorted(actual ^ expected)}')
    files = {}
    for name in FORTH_FILES:
        data = regular(repo, name)
        source_text(data, name)
        files[name] = data
    for name, digest in prepared.items():
        relative(name)
        if not isinstance(digest, str) or not HEX.fullmatch(digest):
            raise ValueError(f'invalid prepared source hash: {name}')
        data = regular(sources, name)
        source_text(data, name)
        if sha(data) != digest:
            raise ValueError(f'prepared source hash mismatch: {name}')
        files[SOURCE_PREFIX + name] = data
    if SOURCE_PREFIX + 'direct-input.c' not in files:
        raise ValueError('prepared manifest lacks direct-input.c')
    return files


def static_amd64(data, name):
    if len(data) < 64 or data[:7] != b'\x7fELF\x02\x01\x01':
        raise ValueError(f'not an ELF64 little-endian executable: {name}')
    kind, machine = struct.unpack_from('<HH', data, 16)
    if kind != 2 or machine != 62:
        raise ValueError(f'not an AMD64 ET_EXEC: {name}')
    entry, phoff = struct.unpack_from('<QQ', data, 24)
    phsize, phnum = struct.unpack_from('<HH', data, 54)
    if phsize != 56 or not phnum or phoff + phsize * phnum > len(data):
        raise ValueError(f'invalid program header table: {name}')
    loads = []
    for i in range(phnum):
        typ, flags, offset, vaddr, _, filesz, memsz, _ = struct.unpack_from(
            '<IIQQQQQQ', data, phoff + i * phsize)
        if typ in (2, 3):
            raise ValueError(f'dynamic segment/interpreter in executable: {name}')
        if typ == 1:
            if filesz > memsz or offset + filesz > len(data):
                raise ValueError(f'invalid load segment: {name}')
            loads.append((vaddr, memsz, flags))
    if not any(flags & 1 and addr <= entry < addr + size for addr, size, flags in loads):
        raise ValueError(f'entry point outside executable load segment: {name}')


def inventory(root):
    executables = []
    for path in root.rglob('*'):
        if path.is_symlink():
            raise ValueError(f'symlink in isolated root: {path}')
        mode = path.stat().st_mode
        if stat.S_ISREG(mode):
            name = path.relative_to(root).as_posix()
            if mode & 0o111:
                executables.append(name)
        elif not stat.S_ISDIR(mode):
            raise ValueError(f'nonregular entry in isolated root: {path}')
    return sorted(executables)


def audit_exec(log):
    boundary = False
    events = []
    for line in log.read_text().splitlines():
        if 'execve(' not in line and 'execveat(' not in line:
            continue
        success = EXEC.fullmatch(line)
        if not boundary:
            if success and success[2] == '/seed-forth':
                boundary = True
            elif success and Path(success[2]).name not in ('unshare', 'chroot'):
                raise ValueError(f'unexpected host setup executable: {line}')
            else:
                continue
        # Fail closed on any unrecognized/failed exec attempt in the root,
        # including execveat, split/truncated trace records and foreign paths.
        if not success or success[2] not in ('/seed-forth', './seed-forth'):
            raise ValueError(f'unexpected in-root exec attempt: {line}')
        events.append({'pid': int(success[1]), 'path': success[2]})
    if not boundary or [e['path'] for e in events] != ['/seed-forth', './seed-forth']:
        raise ValueError(f'expected exactly launcher seed + compiler seed: {events}')
    return events


def skip(reason):
    print(f'SKIP: {reason}', file=sys.stderr)
    return 77


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--repo', type=Path, default=ROOT)
    parser.add_argument('--sources', type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--write-manifest', type=Path)
    mode.add_argument('--manifest', type=Path)
    parser.add_argument('--dest', type=Path, help='new evidence directory, must not exist')
    parser.add_argument('--pin', help='optional independently verified tcc-seed SHA-256')
    args = parser.parse_args()
    repo, sources = args.repo.resolve(), args.sources.resolve()
    seed = regular(repo, 'seed-forth')
    static_amd64(seed, 'seed-forth')
    if sha(seed) != SEED_SHA256:
        raise ValueError('seed-forth differs from the original pinned seed')
    files = source_inputs(repo, sources)
    manifest = {'format': FORMAT, 'seed_sha256': SEED_SHA256,
                'files': {name: sha(data) for name, data in sorted(files.items())}}
    if args.write_manifest:
        with args.write_manifest.open('x') as output:
            json.dump(manifest, output, indent=2, sort_keys=True)
            output.write('\n')
        print(f'Wrote {len(files)} source hashes for review: {args.write_manifest}')
        print('Source preparation/manifest capture only; executable closure was not run.')
        return 0
    if read_json(args.manifest) != manifest:
        raise ValueError('reviewed manifest differs from current compiler/prepared source inputs')
    if args.pin and not HEX.fullmatch(args.pin):
        raise ValueError('--pin must be a lowercase SHA-256')
    if not args.dest:
        parser.error('--dest is required with --manifest')
    dest = args.dest.resolve()
    if dest.exists():
        raise ValueError(f'destination must be new: {dest}')
    programs = {name: shutil.which(name) for name in ('unshare', 'chroot', 'strace')}
    if not all(programs.values()):
        return skip('host verification requires unshare, chroot and strace; none are bootstrap inputs')
    # This is an actual namespace probe; do not substitute an unisolated PASS.
    probe = subprocess.run([programs['unshare'], '--user', '--map-root-user', '--mount',
                            sys.executable, '-c', 'pass'], capture_output=True)
    if probe.returncode:
        return skip('user/mount namespace unavailable: ' + probe.stderr.decode(errors='replace').strip())
    dest.mkdir(parents=True)
    root = dest / 'root'
    root.mkdir()
    for name, data in files.items():
        target = root / relative(name)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o444)
    (root / 'seed-forth').write_bytes(seed)
    (root / 'seed-forth').chmod(0o555)
    (root / 'tmp').mkdir()
    before = inventory(root)
    if before != ['seed-forth'] or (root / 'bin').exists() or (root / 'usr').exists():
        raise ValueError('initial executable/root inventory is not source-only')
    (dest / 'reviewed-input-manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    # Confirm chroot and ptrace work before accepting the build audit. Python,
    # strace, unshare and chroot are host harness tools, never staged in root.
    probe_log = dest / 'probe-exec.log'
    probe = subprocess.run([programs['strace'], '-f', '-qq', '-s', '4096', '-o', str(probe_log),
                            '-e', 'trace=execve,execveat', programs['unshare'], '--user',
                            '--map-root-user', '--mount', programs['chroot'], str(root), '/seed-forth'],
                           input=b'', capture_output=True, env={'PATH': '', 'LC_ALL': 'C'})
    if probe.returncode:
        return skip('isolated chroot/syscall audit unavailable: ' + probe.stderr.decode(errors='replace').strip())
    log = dest / 'exec.log'
    print('Initial executable inventory: seed-forth only; no /bin or /usr', flush=True)
    command = [programs['strace'], '-f', '-qq', '-s', '4096', '-o', str(log),
               '-e', 'trace=execve,execveat', programs['unshare'], '--user', '--map-root-user',
               '--mount', programs['chroot'], str(root), '/seed-forth']
    with (root / START).open('rb') as stdin, (dest / 'launcher.stdout').open('wb') as stdout, \
            (dest / 'launcher.stderr').open('wb') as stderr:
        result = subprocess.run(command, stdin=stdin, stdout=stdout, stderr=stderr,
                                env={'PATH': '', 'LC_ALL': 'C'}, close_fds=True)
    if result.returncode:
        raise ValueError(f'isolated launcher failed with status {result.returncode}; inspect {dest}')
    events = audit_exec(log)
    if (dest / 'launcher.stdout').stat().st_size or (dest / 'launcher.stderr').stat().st_size:
        raise ValueError(f'unexpected launcher diagnostics; inspect {dest}')
    if (root / 'build-out/tcc-compile.stdout').stat().st_size:
        raise ValueError('compiler emitted unexpected Forth diagnostics')
    after = inventory(root)
    if after != sorted(['seed-forth', PRODUCT]):
        raise ValueError(f'unexpected final executable inventory: {after}')
    for name, data in files.items():
        if regular(root, name) != data:
            raise ValueError(f'source changed during isolated build: {name}')
    if regular(root, 'seed-forth') != seed:
        raise ValueError('original seed changed during isolated build')
    for path in root.rglob('*'):
        if path.is_file():
            name = path.relative_to(root).as_posix()
            if name not in ('seed-forth', PRODUCT):
                source_text(path.read_bytes(), name)
    product = regular(root, PRODUCT)
    static_amd64(product, PRODUCT)
    digest = sha(product)
    if args.pin and digest != args.pin:
        raise ValueError(f'product pin differs: {digest} != {args.pin}')
    report = {'result': 'PASS', 'scope': 'direct seed-only compilation closure; no downstream fixed-point claim',
              'initial_executables': before, 'final_executables': after, 'source_files': len(files),
              'in_root_execs': events, 'product': PRODUCT, 'product_bytes': len(product),
              'product_sha256': digest, 'expected_product_pin': args.pin,
              'source_preparation': 'outside executable closure, verified by prepared and reviewed manifests',
              'audit': 'exec.log (host strace; every in-root exec attempt checked)'}
    (dest / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
