#!/usr/bin/env python3
"""Execute original GCC ffs target bytes against an independent Python oracle.

The C input and target object are produced/consumed by Forth only. The Python
oracle maps the object's relocation-free text; it does not compile or link it.
This is one bounded libiberty unit, not a complete GCC bootstrap.
"""
from pathlib import Path
import ctypes
import hashlib
import json
import mmap
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE_SHA256 = '514a4bfc11ca70e48d818c9dccfb13b3c7f502371b0b54d0b13c5dec7220ecec'


def main():
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        ROOT / 'build-out/direct-gcc-inputs/gcc-source/libiberty/ffs.c')
    if not source.is_file():
        print('SKIP: provide original pinned GCC 4.0.4 libiberty/ffs.c path')
        raise SystemExit(77)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == SOURCE_SHA256
    with tempfile.TemporaryDirectory(prefix='review-sysv-ffs.') as temp:
        obj = Path(temp) / 'ffs.o'
        subprocess.run([str(ROOT / 'tests/gcc/sysv-object-compile.sh'),
                        str(source), str(obj)], check=True)
        data = obj.read_bytes()
        elf = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
        sections = [struct.unpack_from('<IIQQQQIIQQ', data, elf[6]+i*elf[11])
                    for i in range(elf[12])]
        assert all(not section[5] for section in sections if section[1] in (4, 9)), (
            'raw-code oracle requires a relocation-free object')
        symbols_section = next(section for section in sections if section[1] == 2)
        strings_section = sections[symbols_section[6]]
        strings = data[strings_section[4]:strings_section[4]+strings_section[5]]
        symbols = [struct.unpack_from('<IBBHQQ', data, offset)
                   for offset in range(symbols_section[4],
                                       symbols_section[4]+symbols_section[5],
                                       symbols_section[9])]
        symbol = next(s for s in symbols if strings[s[0]:].split(b'\0', 1)[0] == b'ffs')
        section = sections[symbol[3]]
        code = data[section[4]:section[4]+section[5]]
        area = mmap.mmap(-1, len(code), prot=mmap.PROT_READ|mmap.PROT_WRITE|mmap.PROT_EXEC)
        area.write(code)
        address = ctypes.addressof(ctypes.c_char.from_buffer(area))+symbol[4]
        ffs = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int)(address)
        values = [0, 0xffffffff, 0x80000000, 0x7fffffff]+list(range(65536))
        values += [1 << i for i in range(32)]
        values += [0xffffffff ^ (1 << i) for i in range(32)]
        for value in values:
            expected = (value & -value).bit_length()
            actual = ffs(ctypes.c_int(value).value)
            assert actual == expected, (hex(value), actual, expected)
        del ffs
        area.close()
        print(f'PASS: original GCC ffs raw Forth text versus Python low-bit oracle; {len(values)} values')
        print(json.dumps({'source_sha256': SOURCE_SHA256,
                          'object_sha256': hashlib.sha256(data).hexdigest(),
                          'comparisons': len(values),
                          'host_compiler_or_linker_used': False}, sort_keys=True))


if __name__ == '__main__':
    main()
