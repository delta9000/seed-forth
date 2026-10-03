#!/usr/bin/env python3
"""Independent bounded ELF contract review; production artifacts are Forth-only.

SF_REVIEW_ROOT can select a frozen source snapshot. Python only inspects or
corrupts test bytes. readelf and ld are independent test oracles.
"""
from pathlib import Path
import hashlib
import json
import os
import resource
import signal
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(os.environ.get('SF_REVIEW_ROOT', Path(__file__).resolve().parents[2])).resolve()
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='review-elf-', dir=ROOT / 'build-out'))
PARTS = ('010-lib.fth', '020-cc-arena.fth', '030-cc-io.fth')
BASE = '\n'.join((ROOT / p).read_text() for p in PARTS)
WRITER = BASE + '\n' + (ROOT / '081-cc-object.fth').read_text()
LINKER = BASE + '\n' + (ROOT / '140-cc-link.fth').read_text()
HASHES = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
          for p in (*PARTS, '081-cc-object.fth', '140-cc-link.fth', 'seed-forth')}
COUNT = 0
CHECKS = []


def word(name, path):
    assert not any(c.isspace() for c in str(path))
    return f'\ncreate {name} s, {path} [lit] 0 c,\n'


def forth(name, source, status=0, file_limit=None):
    global COUNT
    COUNT += 1
    def set_limit():
        resource.setrlimit(resource.RLIMIT_FSIZE, (file_limit, file_limit))
        signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    result = subprocess.run([ROOT / 'seed-forth'], input=source.encode(),
                            capture_output=True, timeout=30,
                            preexec_fn=set_limit if file_limit else None)
    assert result.returncode == status, (name, status, result.returncode, result.stderr)
    assert not result.stdout, (name, result.stdout)
    assert (f'error {status}'.encode() in result.stderr if status else not result.stderr), (name, result.stderr)
    CHECKS.append({'name': name, 'status': status})
    return result


def link(name, paths, status=0, destination=None, file_limit=None):
    destination = destination or OUT / name
    was_directory = destination.is_dir()
    before = destination.read_bytes() if destination.is_file() else None
    source = LINKER + '\n: review-assert 0= if, [lit] 249 die then, ;\nlnk-init\n[lit] 314159\n'
    for i, path in enumerate(paths):
        source += word(f'in-{i}', path) + f'in-{i} lnk-add-object\n'
    source += 'create entry s, _start\nentry [lit] 6 lnk-entry\n'
    source += word('dest', destination) + 'dest lnk-link\n'
    source += '[lit] 314159 = review-assert\n'
    forth(name, source, status, file_limit)
    if status:
        if before is not None:
            assert destination.read_bytes() == before
        elif was_directory:
            assert destination.is_dir()
        else:
            assert not destination.exists()
    else:
        assert destination.is_file()
    assert not list(OUT.glob('*.lnk-*')), 'temporary output leaked'
    return destination


def execute(path, status=42):
    result = subprocess.run([path], capture_output=True, timeout=5)
    assert (result.returncode, result.stdout, result.stderr) == (status, b'', b''), (path, result)


def u16(data, offset): return struct.unpack_from('<H', data, offset)[0]
def u32(data, offset): return struct.unpack_from('<I', data, offset)[0]
def u64(data, offset): return struct.unpack_from('<Q', data, offset)[0]
def sh(data, index): return u64(data, 40) + 64 * index

def row(data, index):
    return struct.unpack_from('<IIQQQQIIQQ', data, sh(data, index))


def symbol(data, name):
    table, strings = row(data, 7), row(data, 8)
    for i in range(table[5] // 24):
        at = table[4] + 24 * i
        start = strings[4] + u32(data, at)
        if data[start:data.index(0, start)].decode() == name:
            return i, at
    raise AssertionError(name)


def put(data, at, value, width=8):
    data[at:at + width] = (value % (1 << (8 * width))).to_bytes(width, 'little')


def mutate(path, name, edit):
    data = bytearray(path.read_bytes())
    edit(data)
    result = OUT / (name + '.o')
    result.write_bytes(data)
    return result


# Independent fixture: initialized data holds a relocated pointer; BSS starts
# after a page boundary and is read by the executable before adding 42.
a, b = OUT / 'review-a.o', OUT / 'review-b.o'
source = WRITER + word('a-path', a) + word('b-path', b) + '''
create start-name s, _start
create zero-name s, zero
create local-name s, local_value
create unused-name s, unused_weak
variable zero-id
variable local-id
cc-obj-init
[lit] 4096 cc-obj-align
[lit] 139 cc-obj-byte [lit] 61 cc-obj-byte [lit] 0 cc-obj-4le
[lit] 131 cc-obj-byte [lit] 199 cc-obj-byte [lit] 42 cc-obj-byte
[lit] 184 cc-obj-byte [lit] 60 cc-obj-4le [lit] 15 cc-obj-byte [lit] 5 cc-obj-byte
start-name [lit] 6 cc-obj-global cc-obj-func cc-obj-default cc-obj-text [lit] 0 [lit] 16 cc-obj-symbol drop
zero-name [lit] 4 cc-obj-global cc-obj-object cc-obj-default cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol zero-id !
local-name [lit] 11 cc-obj-local cc-obj-notype cc-obj-hidden cc-obj-abs [lit] 42 [lit] 0 cc-obj-symbol local-id !
unused-name [lit] 11 cc-obj-weak cc-obj-notype cc-obj-default cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol drop
cc-obj-rodata cc-obj-use [lit] 4096 cc-obj-align
[lit] 17 cc-obj-byte [lit] 34 cc-obj-byte [lit] 51 cc-obj-byte
cc-obj-data cc-obj-use [lit] 16 cc-obj-align [lit] 16 cc-obj-reserve drop
cc-obj-text [lit] 2 cc-obj-pc32 zero-id @ [lit] 0 [lit] 4 - cc-obj-reloc
cc-obj-data [lit] 0 cc-obj-r64 zero-id @ [lit] 0 cc-obj-reloc
cc-obj-data [lit] 8 cc-obj-r32 local-id @ [lit] 0 cc-obj-reloc
cc-obj-bss cc-obj-use [lit] 4096 cc-obj-align [lit] 4 cc-obj-reserve drop
a-path cc-obj-write
cc-obj-init
cc-obj-data cc-obj-use [lit] 4 cc-obj-reserve drop
local-name [lit] 11 cc-obj-local cc-obj-notype cc-obj-hidden cc-obj-abs [lit] 99 [lit] 0 cc-obj-symbol local-id !
cc-obj-data [lit] 0 cc-obj-r32 local-id @ [lit] 0 cc-obj-reloc
cc-obj-bss cc-obj-use [lit] 4096 cc-obj-align [lit] 8192 cc-obj-reserve drop
zero-name [lit] 4 cc-obj-global cc-obj-object cc-obj-default cc-obj-bss [lit] 4096 [lit] 4 cc-obj-symbol drop
b-path cc-obj-write
'''
forth('independent-writer-fixture', source)
exe = link('independent-image', [a, b])
execute(exe)
execute(link('reversed-image', [b, a]))
image = exe.read_bytes()
rx, rw = 64, 120
assert (u32(image, rx + 4), u32(image, rw + 4)) == (5, 6)
assert u64(image, rw + 8) % 4096 == 0
assert u64(image, rw + 16) % 4096 == 0
assert u64(image, rw + 40) > u64(image, rw + 32)
assert len(image) == u64(image, rw + 8) + u64(image, rw + 32)
data_at = u64(image, rw + 8)
assert u32(image, data_at + 8) == 42 and u32(image, data_at + 16) == 99
assert u64(image, data_at) % 4096 == 0
assert image[8192:8195] == bytes((17, 34, 51))
for oracle in ('readelf', 'ld'):
    assert shutil.which(oracle), f'review test oracle missing: {oracle}'
for path in (a, b, exe):
    inspected = subprocess.run(['readelf', '-aW', path], capture_output=True)
    assert inspected.returncode == 0 and not inspected.stderr, (path, inspected.stderr)
    (OUT / (path.name + '.readelf.txt')).write_bytes(inspected.stdout)
host_exe = OUT / 'host-oracle'
subprocess.run(['ld', '-e', '_start', '-o', host_exe, a, b], check=True, capture_output=True)
execute(host_exe)

# PC-relative exact bounds and one-past cases are independent of the existing
# gate's absolute 32/32S boundaries. P is the known first text relocation site.
site = 0x401002
for kind in (2, 4):
    for displacement in (-2**31, 2**31 - 1, -2**31 - 1, 2**31):
        name = f'pc-{kind}-{displacement}'
        def edit(data, kind=kind, displacement=displacement):
            index, at = symbol(data, 'local_value')
            put(data, at + 8, site + displacement)
            reloc = row(data, 5)[4]
            put(data, reloc + 8, (index << 32) | kind)
            put(data, reloc + 16, 0)
            put(data, row(data, 6)[4] + 24 + 16, 42 - (site + displacement))
        obj = mutate(a, name, edit)
        good = -2**31 <= displacement < 2**31
        result = link(name, [obj, b], 0 if good else 254)
        if good:
            assert u32(result.read_bytes(), 4098) == displacement % 2**32

# Absolute 64-bit relocations retain modulo-2^64 semantics, including a wrap.
for value, addend in ((2**64 - 1, 0), (2**64 - 1, 2), (0, -1)):
    name = f'abs64-{value}-{addend}'
    def edit(data, value=value, addend=addend):
        index, at = symbol(data, 'local_value')
        put(data, at + 8, value)
        reloc = row(data, 6)[4]
        put(data, reloc + 8, (index << 32) | 1)
        put(data, reloc + 16, addend)
        # Keep the existing separate R32 reference in range.
        put(data, reloc + 24 + 16, 42 - value)
    obj = mutate(a, name, edit)
    result = link(name, [obj, b]).read_bytes()
    assert u64(result, u64(result, rw + 8)) == (value + addend) % 2**64

# The linker supports a larger alignment bound than the writer. A mutated
# contract-compatible fixture checks actual virtual placement at that bound.
maxalign = mutate(b, 'maximum-alignment', lambda x: put(x, sh(x, 4) + 48, 2**20))
aligned = link('maximum-alignment', [a, maxalign])
execute(aligned)
assert u64(aligned.read_bytes(), data_at) % 2**20 == 4096

bad_cases = [
    ('elf-version', lambda x: put(x, 20, 2, 4)),
    ('null-section-nonzero', lambda x: put(x, sh(x, 0) + 24, 1)),
    ('null-symbol-nonzero', lambda x: put(x, row(x, 7)[4] + 8, 1)),
    ('symbol-visibility-upper-bit', lambda x: put(x, symbol(x, '_start')[1] + 5, 128, 1)),
    ('symbol-size-overflow', lambda x: put(x, symbol(x, '_start')[1] + 16, 2**64 - 1)),
    ('undefined-nonzero-size', lambda x: put(x, symbol(x, 'zero')[1] + 16, 1)),
    ('strtab-leading-byte', lambda x: put(x, row(x, 8)[4], 1, 1)),
    ('shstrtab-leading-byte', lambda x: put(x, row(x, 9)[4], 1, 1)),
    ('symtab-size-remainder', lambda x: put(x, sh(x, 7) + 32, row(x, 7)[5] - 1)),
    ('symtab-local-overrun', lambda x: put(x, sh(x, 7) + 44, row(x, 7)[5] // 24 + 1, 4)),
    ('strtab-size-zero', lambda x: put(x, sh(x, 8) + 32, 0)),
    ('shstrtab-size-zero', lambda x: put(x, sh(x, 9) + 32, 0)),
    ('shstrtab-alignment', lambda x: put(x, sh(x, 9) + 48, 2)),
    ('rela-data-wrong-target', lambda x: put(x, sh(x, 6) + 44, 1, 4)),
    ('common-symbol', lambda x: put(x, symbol(x, 'local_value')[1] + 6, 65522, 2)),
    ('extended-section-index', lambda x: put(x, symbol(x, 'local_value')[1] + 6, 65535, 2)),
    ('tls-symbol', lambda x: put(x, symbol(x, '_start')[1] + 4, 0x16, 1)),
    ('extra-section', lambda x: put(x, 60, 11, 2)),
]
preserved = OUT / 'preserved-output'
preserved.write_bytes(b'previous complete output\n')
for name, edit in bad_cases:
    link(name, [mutate(a, name, edit), b], 250, preserved)

# Definition ownership survives reset and repeated links. Release is safe to
# repeat; a stack sentinel detects unintended data-stack residues across APIs.
source = LINKER + word('a', a) + word('b', b) + word('dest', OUT / 'repeated')
source += '''
create en s, _start
variable iteration
: review-assert 0= if, [lit] 249 die then, ;
[lit] 314159
: one-session
  lnk-init a lnk-add-object b lnk-add-object en [lit] 6 lnk-entry
  dest lnk-link dest lnk-link lnk-release lnk-release ;
: sessions
  [lit] 0 iteration !
  begin, iteration @ [lit] 40 < while,
    one-session [lit] 1 iteration +!
  repeat, ;
sessions
[lit] 314159 = review-assert
'''
forth('forty-sessions-with-double-link-and-release', source)
execute(OUT / 'repeated')

# Probe every previously owned page through Linux mincore after release. The
# kernel must report ENOMEM, independently confirming that the object, global
# table, and image mappings are actually gone rather than only reset in Forth.
source = LINKER + word('a', a) + word('b', b) + word('dest', OUT / 'release-image')
source += '''
create en s, _start
create owned [lit] 64 allot
create residency [lit] 1 allot
variable check-address
variable check-bytes
variable check-index
: review-assert 0= if, [lit] 249 die then, ;
: remember-object
  lnk-object dup @ owned check-index @ + !
  [lit] 8 + @ owned check-index @ + [lit] 8 + ! ;
lnk-init a lnk-add-object b lnk-add-object en [lit] 6 lnk-entry dest lnk-link
[lit] 0 check-index ! [lit] 0 remember-object
[lit] 16 check-index ! [lit] 1 remember-object
lnk-globals @ owned [lit] 32 + !
lnk-hash-cap [lit] 32 * owned [lit] 40 + !
lnk-image @ owned [lit] 48 + ! lnk-file-size @ owned [lit] 56 + !
lnk-release
: check-unmapped
  [lit] 0 check-index !
  begin, check-index @ [lit] 64 < while,
    owned check-index @ + @ check-address !
    owned check-index @ + [lit] 8 + @ [lit] 4096 lnk-align check-bytes !
    begin, check-bytes @ while,
      check-address @ [lit] 4096 residency [lit] 0 [lit] 0 [lit] 0 [lit] 27 syscall6
      [lit] 0 [lit] 12 - = review-assert
      [lit] 4096 check-address +! [lit] 4096 check-bytes -!
    repeat,
    [lit] 16 check-index +!
  repeat, ;
check-unmapped
'''
forth('kernel-confirms-all-owned-pages-unmapped', source)

# Resource limits fail before a large BSS allocates any output image.
large_bss = mutate(b, 'bss-layout-cap', lambda x: put(x, sh(x, 4) + 32, 2**28))
link('bss-layout-cap', [a, large_bss], 251, preserved)
too_large_bss = mutate(b, 'bss-input-cap', lambda x: put(x, sh(x, 4) + 32, 2**28 + 1))
link('bss-input-cap', [a, too_large_bss], 251, preserved)

# A failed final rename and failed opening of the sibling temporary must leave
# input and destination bytes intact and remove any temporary created by us.
directory = OUT / 'destination-is-directory'
directory.mkdir()
link('rename-fails-to-directory', [a, b], 255, directory)
link('short-write-EFBIG-preserves-output', [a, b], 255, preserved, 128)
missing = OUT / 'missing-parent' / 'file'
link('open-fails-missing-parent', [a, b], 255, missing)
for alias_kind in ('hardlink', 'symlink'):
    alias = OUT / alias_kind
    if alias_kind == 'hardlink': os.link(a, alias)
    else: alias.symlink_to(a)
    before = a.read_bytes()
    link(f'input-{alias_kind}', [a, b], 255, alias)
    assert a.read_bytes() == before

(OUT / 'results.json').write_text(json.dumps({'source_hashes': HASHES,
    'seed_runs': COUNT, 'checks': CHECKS}, indent=2) + '\n')
print(f'review-elf: {COUNT} independent seed runs passed; 40 reset sessions; host oracles agree')
print(f'review-elf: evidence: {OUT}')
