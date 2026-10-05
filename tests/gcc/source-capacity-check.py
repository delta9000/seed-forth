#!/usr/bin/env python3
"""Direct-driver source-text and rodata/data bounds, end to end.

The direct-GCC profile holds the live include stack in a mapped pool and the
expanded translation unit in a mapped source slice; both share one 7 MiB
bound. Rodata and data each have 2 MiB. Every case runs the real driver:
the exact bound compiles, one byte more fails with the owning error code and
publishes nothing (an earlier output file keeps its bytes). See
workspace-capacity-README.md for the measurements behind the bounds.
"""
from pathlib import Path
import hashlib, json, resource, struct, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / 'tools/gcc-direct-cc.py'
SOURCE_CAP = 7 * 1024 * 1024      # cc-src-direct-cap = cc-prep-inc-direct-cap
SECTION_CAP = 2 * 1024 * 1024     # cc-obj-section-direct-cap
resource.setrlimit(resource.RLIMIT_AS, (1024 ** 3, 1024 ** 3))
(ROOT / 'build-out').mkdir(exist_ok=True)
WORK = Path(tempfile.mkdtemp(prefix='source-capacity-', dir=ROOT / 'build-out'))
records = []

# Policy constants are spelled once in the Forth sources; check them here.
io = (ROOT / '030-cc-io.fth').read_text()
prep = (ROOT / '040-cc-prep.fth').read_text()
obj = (ROOT / '081-cc-object.fth').read_text()
assert f'[lit] {SOURCE_CAP} constant cc-src-direct-cap\n' in io
assert 'cc-src-direct-cap constant cc-prep-inc-direct-cap\n' in prep
assert f'[lit] {SECTION_CAP} constant cc-obj-section-direct-cap\n' in obj


def skipped(size, inner=b''):
    """size bytes: an optional nested #include, then a skipped #if 0 group.
    Skipped lines expand to bare newlines, so the pool, not the expanded
    source, is the binding bound."""
    head, tail = inner + b'#if 0\n', b'#endif\n'
    room = size - len(head) - len(tail)
    assert room >= 0
    line = b'x' * 1023 + b'\n'
    body = line * (room // len(line))
    body += b'x' * (room - len(body) - 1) + b'\n' if room > len(body) else b''
    data = head + body + tail
    assert len(data) == size
    return data


def text(size):
    """size bytes of ordinary text lines, copied unchanged by -E."""
    line = b'0' * 1023 + b'\n'
    data = line * (size // len(line))
    data += b'0' * (size - len(data) - 1) + b'\n' if size > len(data) else b''
    assert len(data) == size
    return data


def cc(name, files, args, status, code=None):
    """Run the driver on files[main]; with status, check the diagnostic and
    that neither an absent nor an existing output changes."""
    case = WORK / name
    case.mkdir()
    for path, data in files.items():
        (case / path).write_bytes(data)
    outputs = [False, True] if status else [False]
    for existing in outputs:
        out = case / ('existing.out' if existing else 'fresh.out')
        if existing:
            out.write_bytes(b'preserve earlier output\n')
        p = subprocess.run([sys.executable, DRIVER, *args, 'main.c', '-o', out.name],
                           cwd=case, capture_output=True, timeout=600)
        assert p.returncode == status and p.stdout == b'', (name, p)
        if status:
            assert p.stderr.startswith(b'cc: line ') and f': error {code}\n'.encode() in p.stderr, (name, p.stderr)
            assert out.read_bytes() == b'preserve earlier output\n' if existing else not out.exists(), name
            assert sorted(x.name for x in case.iterdir()) == sorted(list(files) + ([out.name] if existing else [])), name
        else:
            assert p.stderr == b'', (name, p.stderr)
        records.append({'case': name + ('-existing' if existing else ''), 'status': p.returncode})
    return case / 'fresh.out'


def sections(path):
    data = path.read_bytes()
    shoff, = struct.unpack_from('<Q', data, 40)
    count, names = struct.unpack_from('<HH', data, 60)
    rows = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + 64 * i) for i in range(count)]
    table = data[rows[names][4]:rows[names][4] + rows[names][5]]
    return {table[r[0]:].split(b'\0', 1)[0].decode(): r[5] for r in rows}


main = b'#include "pool.h"\nint main(void) { return 0; }\n'
# The raw reader keeps one byte to see end of file: cap-1 live bytes fit.
o = cc('pool-exact', {'main.c': main, 'pool.h': skipped(SOURCE_CAP - 1)}, ['-c'], 0)
assert sections(o)['.text'] > 0
cc('pool-one-past', {'main.c': main, 'pool.h': skipped(SOURCE_CAP)}, ['-c'], 32, 32)
# The pool holds the live stack: an includer and its include count together.
inner = b'#include "inner.h"\n'
for name, total, status in [('pool-nested-exact', SOURCE_CAP - 1, 0), ('pool-nested-one-past', SOURCE_CAP, 32)]:
    cc(name, {'main.c': main, 'pool.h': skipped(total - 4096, inner), 'inner.h': skipped(4096)},
       ['-c'], status, 32)
# Closed files give their bytes back: two full headers in sequence fit.
cc('pool-sequential', {'main.c': b'#include "a.h"\n#include "b.h"\nint main(void) { return 0; }\n',
                       'a.h': skipped(SOURCE_CAP - 1), 'b.h': skipped(SOURCE_CAP - 1)}, ['-c'], 0)
# Expanded source: two halves plus each directive line's newline.
seq = b'#include "a.h"\n#include "b.h"\n'
half = (SOURCE_CAP - 2) // 2
o = cc('expanded-exact', {'main.c': seq, 'a.h': text(half), 'b.h': text(SOURCE_CAP - 2 - half)}, ['-E'], 0)
assert o.stat().st_size == SOURCE_CAP, o.stat().st_size
cc('expanded-one-past', {'main.c': seq, 'a.h': text(half), 'b.h': text(SOURCE_CAP - 1 - half)}, ['-E'], 36, 36)
# Data payload: an initialized object of exactly the section bound.
o = cc('data-exact', {'main.c': f'char d[{SECTION_CAP}] = {{1}};\n'.encode()}, ['-c'], 0)
assert sections(o)['.data'] == SECTION_CAP
cc('data-one-past', {'main.c': f'char d[{SECTION_CAP + 1}] = {{1}};\n'.encode()}, ['-c'], 245, 245)

report = {'status': 'PASS', 'seed_sha256': hashlib.sha256((ROOT / 'seed-forth').read_bytes()).hexdigest(),
          'source_cap': SOURCE_CAP, 'section_cap': SECTION_CAP, 'cases': records}
(WORK / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(f'PASS {len(records)} source-capacity cases: {WORK}/report.json')
