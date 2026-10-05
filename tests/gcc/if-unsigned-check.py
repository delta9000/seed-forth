#!/usr/bin/env python3
"""LP64 #if signedness; host preprocessing is an independent oracle only."""
from pathlib import Path
import resource
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / 'tools/gcc-direct-cc.py'
FIXTURE = ROOT / 'tests/gcc/if-unsigned-fixture.c'
resource.setrlimit(resource.RLIMIT_AS, (1024**3, 1024**3))

def run(command):
    return subprocess.run(list(map(str, command)), cwd=ROOT,
                          capture_output=True, text=True, timeout=180)

actual = run([DRIVER, '-E', FIXTURE])
expected = run(['gcc', '-std=c99', '-E', '-P', FIXTURE])
assert actual.returncode == expected.returncode == 0, (actual, expected)
expressions = [line[4:] for line in FIXTURE.read_text().splitlines()
               if line.startswith('#if ')]
a, b = actual.stdout.split(), expected.stdout.split()
assert len(a) == len(b) == len(expressions), (a, b)
for expression, got, want in zip(expressions, a, b):
    assert got == want, (expression, got, want)
with tempfile.TemporaryDirectory(prefix='if-unsigned-') as work:
    for expression in ('1 / 0', '1u / 0', '1 % 0u',
                       '1 && (1u / 0)', '0 || (1u % 0)',
                       '1 ? (1u / 0) : 0', '0 ? 0 : (1u % 0)'):
        source = Path(work) / 'zero.c'
        source.write_text(f'#if {expression}\nyes\n#endif\n')
        result = run([DRIVER, '-E', source])
        assert result.returncode == 124 and 'error 124' in result.stderr, result
print(f'PASS: {len(expressions)} #if expressions match GCC; evaluated zero divisors retain code 124')
