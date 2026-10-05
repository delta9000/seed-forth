#!/usr/bin/env python3
"""GCC configure's grouped object-pointer casts and general type semantics."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(tempfile.mkdtemp(prefix='grouped-pointer-type-', dir=ROOT / 'build-out'))
DIRECT = ['python3', ROOT / 'tools/gcc-direct-cc.py']


def run(command, expected=0):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=180)
    assert result.returncode == expected, (command, result.returncode, result.stderr.decode())
    return result


fixture = ROOT / 'tests/gcc/grouped-pointer-type.c'
run(DIRECT + [fixture, '-o', WORK / 'forth'])
run([WORK / 'forth'])
for opt in ['-O0', '-O2']:
    run(['gcc', '-std=gnu89', opt, fixture, '-o', WORK / ('host' + opt)])
    run([WORK / ('host' + opt)])

# Preserve the exact old gcc_AC_CHECK_DECL spelling against real seed headers.
for name in ['malloc', 'getenv', 'free', 'calloc', 'realloc', 'strstr', 'atol']:
    source = WORK / (name + '.c')
    source.write_text('#include <stdlib.h>\n#include <string.h>\n'
                      'int main(void){\n#ifndef ' + name + '\n'
                      'char *(*pfn) = (char *(*)) ' + name + ';\n#endif\nreturn 0;}\n')
    run(DIRECT + ['-c', source, '-o', WORK / (name + '.o')])
    run(['gcc', '-std=gnu89', '-I', ROOT / 'runtime/gcc-seed/include',
         '-c', source, '-o', WORK / (name + '-host.o')])

# Adding grouped stars must enforce the total depth, not just the group depth.
source = WORK / 'overflow.c'
source.write_text('int main(void){return sizeof(int ' + '*' * 254 + ' (**));}\n')
for mode in ['object', 'mapped']:
    output = WORK / ('overflow-' + mode)
    marker = b'previous complete artifact\n'
    output.write_bytes(marker)
    command = (DIRECT + ['-c', source, '-o', output] if mode == 'object'
               else [ROOT / 'tests/gcc/sysv-compile.sh', source, output])
    result = run(command, 231)
    assert b'error 231' in result.stderr and output.read_bytes() == marker

# A missing declaration must still fail; accepting the cast is not a cache override.
source = WORK / 'undeclared.c'
source.write_text('int main(void){char *(*pfn)=(char *(*)) undeclared;}\n')
for command in [DIRECT, ['gcc', '-std=gnu89']]:
    result = subprocess.run(list(map(str, command + ['-c', source, '-o', WORK / 'missing.o'])),
                            cwd=ROOT, capture_output=True, timeout=180)
    assert result.returncode != 0, result
print('PASS: grouped pointer bases, depths, descriptors and GCC declaration probes match host GCC; overflow and undeclared names reject')
