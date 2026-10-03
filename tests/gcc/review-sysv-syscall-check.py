#!/usr/bin/env python3
"""Independent syscall-object oracle; no host tool produces target .text."""
from pathlib import Path
import ctypes
import hashlib
import json
import os
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
INPUTS = ['010-lib.fth', '020-cc-arena.fth', '030-cc-io.fth',
          '081-cc-object.fth', '122-cc-sysv-runtime.fth']
EXPECTED = bytes.fromhex('48 89 f8 48 89 f7 48 89 d6 48 89 ca '
                         '4d 89 c2 4d 89 c8 4c 8b 4c 24 08 0f 05 c3')


def main():
    if not shutil.which('gcc') or not shutil.which('objdump'):
        raise SystemExit('SKIP: gcc and objdump needed only as ABI/disassembly oracles')
    hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in INPUTS}
    with tempfile.TemporaryDirectory(prefix='review-sysv-syscall.') as temp:
        work = Path(temp); obj = work / 'syscall.o'
        driver = 'create outpath\n' + ''.join(
            f'[lit] {b} c,\n' for b in bytes(obj)+b'\0')
        driver += 'cc-sysrt-object outpath cc-obj-write bye\n'
        forth = b''.join((ROOT / name).read_bytes() for name in INPUTS)+driver.encode()
        result = subprocess.run([str(ROOT / 'seed-forth')], input=forth, capture_output=True)
        assert result.returncode == 0 and not result.stdout and not result.stderr, repr(result)
        data = obj.read_bytes()
        elf = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
        sections = [struct.unpack_from('<IIQQQQIIQQ', data, elf[6]+i*elf[11])
                    for i in range(elf[12])]
        shstr = sections[elf[13]]
        names = data[shstr[4]:shstr[4]+shstr[5]]
        by_name = {names[s[0]:].split(b'\0', 1)[0].decode(): s for s in sections}
        text = by_name['.text']
        assert data[text[4]:text[4]+text[5]] == EXPECTED
        print('PASS: independent ELF parsing verifies the exact 26-byte bridge')
        print(subprocess.run(['objdump', '-d', '-Mintel', str(obj)],
                             capture_output=True, text=True, check=True).stdout)
        library = work / 'syscall.so'
        subprocess.run(['gcc', '-shared', '-Wl,-z,noexecstack', str(obj),
                        '-o', str(library)], check=True)
        lib = ctypes.CDLL(str(library), use_errno=True)
        syscall6 = lib.__seed_syscall6
        syscall6.argtypes = [ctypes.c_long]*7
        syscall6.restype = ctypes.c_long
        assert syscall6(39, 0, 0, 0, 0, 0, 0) == os.getpid()
        ctypes.set_errno(234)
        assert syscall6(3, -1, 0, 0, 0, 0, 0) == -9
        assert ctypes.get_errno() == 234
        assert syscall6(999999, 0, 0, 0, 0, 0, 0) == -38
        fd = os.memfd_create('independent-syscall-review')
        try:
            os.ftruncate(fd, 3*4096)
            payload = b'last-stack-argument-offset-check'
            os.pwrite(fd, payload, 2*4096)
            address = syscall6(9, 0, 4096, 1, 2, fd, 2*4096)
            assert address > 0, address
            try:
                assert ctypes.string_at(address, len(payload)) == payload
            finally:
                assert syscall6(11, address, 4096, 0, 0, 0, 0) == 0
        finally:
            os.close(fd)
        # Use the same independently written six-register sentinel wrapper.
        # The ABI adapter supplies every C argument, including the stack slot.
        guard_c = work / 'guard.c'
        guard_c.write_text(r"""
#include <stdio.h>
#include <unistd.h>
int review_bad_alignment, review_bad_vector_count, review_bad_preservation;
long review_host_callback(void) { return 0; }
long review_host_variadic(void) { return 0; }
extern long review_preserve_guard(long (*)(long),long);
extern long syscall_guard_entry(long);
int main(void) {
    long result=review_preserve_guard(syscall_guard_entry,39);
    if (result!=getpid() || review_bad_preservation) return 1;
    puts("PASS: syscall bridge preserves RBX/RBP/R12/R13/R14/R15 sentinels");
    return 0;
}
""")
        guard_asm = work / 'guard.S'
        guard_asm.write_text(r"""
.text
.globl syscall_guard_entry
.type syscall_guard_entry,@function
syscall_guard_entry:
    sub $8,%rsp
    movq $0,(%rsp)
    xor %esi,%esi
    xor %edx,%edx
    xor %ecx,%ecx
    xor %r8d,%r8d
    xor %r9d,%r9d
    call __seed_syscall6
    add $8,%rsp
    ret
.size syscall_guard_entry,.-syscall_guard_entry
.section .note.GNU-stack,"",@progbits
""")
        guard = work / 'guard'
        subprocess.run(['gcc', '-Wall', '-Wextra', '-Werror', '-O2',
                        str(guard_c), str(guard_asm),
                        str(ROOT / 'tests/gcc/review-sysv-oracle.S'), str(obj),
                        '-o', str(guard)], check=True)
        subprocess.run([str(guard)], check=True)
        print('PASS: Forth syscall object getpid, raw EBADF/ENOSYS, errno preserved, mmap file offset8192')
        current = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in INPUTS}
        assert hashes == current, 'compiler changed during review; rerun'
        print(json.dumps({'object_sha256': hashlib.sha256(data).hexdigest(),
                          'object_bytes': len(data), 'inputs': hashes}, sort_keys=True))


if __name__ == '__main__':
    main()
