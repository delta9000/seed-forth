#!/usr/bin/env python3
"""Static binary32/binary64 initializers, compared byte-for-byte with host GCC.

The Forth compiler computes every static initializer at compile time with
integer operations only (125 and 128). Host GCC never enters production: it
only compiles a renamed copy of the same source as an independent oracle and
the comparison harness. A second, Forth-only executable checks the same
bytes through the seed runtime and Forth linker. Run serially below 1 GiB.
"""
from pathlib import Path
import argparse, hashlib, json, math, random, re, resource, struct, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[2]
TEST = ROOT / 'tests/gcc'
CC = ROOT / 'tools/gcc-direct-cc.py'
FIXTURE = TEST / 'static-float-fixture.c'
OBJECT = re.compile(r'^(?:static )?[\w ]+ \**(sf_\w+)\s*(?:\[|=|;)', re.M)
BLOCK = re.compile(r'^void \*(sf_block_\w+)\(', re.M)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(cmd, status=0, **kw):
    p = subprocess.run([str(x) for x in cmd], capture_output=True, timeout=600, **kw)
    if p.returncode != status:
        raise RuntimeError(f'{cmd}: exit {p.returncode}, expected {status}\n'
                           f'{p.stdout.decode(errors="replace")}{p.stderr.decode(errors="replace")}')
    return p


def f32(x):
    """Round a binary64 value to binary32; None when it overflows."""
    try:
        return struct.unpack('<f', struct.pack('<f', x))[0]
    except OverflowError:
        return None


class Generator:
    """Random typed floating expressions that C and GCC fold without overflow.

    Python evaluation only filters out infinities, NaNs, zero divisors and
    out-of-range integer conversions; GCC supplies every expected byte.
    """

    def __init__(self, seed):
        self.rng = random.Random(seed)

    def literal(self, kind):
        r = self.rng
        digits = ''.join(r.choice('0123456789') for _ in range(r.choice([1, 2, 7, 9, 17, 18, 25, 40])))
        digits = digits.lstrip('0') or '0'
        point = r.randrange(len(digits) + 1)
        mantissa = digits[:point] + '.' + digits[point:]
        if mantissa == '.':
            mantissa = '0.'
        limit = 50 if kind == 'float' else 330
        text = f'{mantissa}e{r.randrange(-limit, limit)}'
        value = float(text)
        if math.isinf(value):
            return None
        if kind == 'float':
            value = f32(value)
            if value is None or abs(value) > 3e38:
                return None
            text += 'f'
        return text, value, kind

    def integer(self):
        r = self.rng
        bits = r.choice([8, 24, 31, 53, 54, 62, 63, 64])
        value = r.getrandbits(bits)
        if bits == 64:
            return f'{value}UL', value, 'int'
        if r.random() < 0.5:
            value = -value
        return (f'{value}L' if value >= 0 else f'({value}L)'), value, 'int'

    @staticmethod
    def convert(value, ctype):
        """The C conversion of an operand to ctype; None on overflow."""
        value = float(value)
        return value if ctype == 'double' else f32(value)

    def expression(self, kind, depth):
        """A (text, value, C type) triple; integer leaves keep type int."""
        r = self.rng
        choice = r.random()
        if depth == 0 or choice < 0.25:
            leaf = self.literal(kind) if r.random() < 0.8 else self.integer()
            return leaf if leaf else self.expression(kind, depth)
        if choice < 0.35:
            inner = self.expression(kind, depth - 1)
            if not inner or inner[2] == 'int':
                return None
            return f'-({inner[0]})', -inner[1], inner[2]
        if choice < 0.45:
            other = 'float' if kind == 'double' else 'double'
            inner = self.expression(other, depth - 1)
            value = inner and self.convert(inner[1], kind)
            return value is not None and inner and (f'({kind})({inner[0]})', value, kind) or None
        left = self.expression(kind, depth - 1)
        right = self.expression(kind if r.random() < 0.7 else 'float', depth - 1)
        if not left or not right or left[2] == right[2] == 'int':
            return None
        ctype = 'double' if 'double' in (left[2], right[2]) else 'float'
        a, b = self.convert(left[1], ctype), self.convert(right[1], ctype)
        op = r.choice('+-*/')
        if a is None or b is None or (op == '/' and b == 0):
            return None
        value = {'+': lambda: a + b, '-': lambda: a - b,
                 '*': lambda: a * b, '/': lambda: a / b}[op]()
        value = self.convert(value, ctype)
        if value is None or math.isinf(value) or math.isnan(value):
            return None
        return f'({left[0]} {op} {right[0]})', value, ctype

    def cases(self, count):
        out = []
        integer_types = [('int', 32, True), ('unsigned', 32, False), ('long', 64, True),
                         ('unsigned long', 64, False), ('short', 16, True),
                         ('unsigned char', 8, False)]
        while len(out) < count:
            target = self.rng.choice(['double', 'double', 'float', 'integer'])
            kind = 'float' if target == 'float' else self.rng.choice(['double', 'float'])
            made = self.expression(kind, self.rng.randrange(4))
            if not made:
                continue
            text, value, ctype = made
            if target == 'integer':
                name, width, signed = self.rng.choice(integer_types)
                whole = math.trunc(value)
                low, high = (-(1 << (width - 1)), 1 << (width - 1)) if signed else (0, 1 << width)
                if not low <= whole < high:
                    continue
                target = name
            elif target == 'float' and self.convert(value, 'float') is None:
                continue
            out.append(f'{target} sf_generated_{len(out)} = {text};')
        return out


def table(names, blocks):
    lines = ['const void *const sf_index_table[] = {']
    lines += [f'  &{n},' for n in names] + ['};', 'const unsigned long sf_index_sizes[] = {']
    lines += [f'  sizeof {n},' for n in names] + ['};']
    return '\n'.join(lines) + '\n'


def harness(names, blocks):
    text = ['#include <stdio.h>', '#include <string.h>',
            'extern const void *const sf_index_table[], *const or_index_table[];',
            'extern const unsigned long sf_index_sizes[], or_index_sizes[];']
    text += [f'void *{b}(unsigned long *);\nvoid *{b.replace("sf_", "or_", 1)}(unsigned long *);' for b in blocks]
    text.append('static const char *const names[] = {' + ','.join(f'"{n}"' for n in names) + '};')
    text.append('''static int same(const char *name, const void *a, unsigned long na,
                const void *b, unsigned long nb) {
  const unsigned char *x = a, *y = b; unsigned long i;
  printf("%s ", name);
  for (i = 0; i < nb; i++) printf("%02x", y[i]);
  printf("\\n");
  if (na == nb && !memcmp(a, b, na)) return 1;
  fprintf(stderr, "%s: Forth ", name);
  for (i = 0; i < na; i++) fprintf(stderr, "%02x", x[i]);
  fprintf(stderr, " != GCC ");
  for (i = 0; i < nb; i++) fprintf(stderr, "%02x", y[i]);
  fprintf(stderr, "\\n");
  return 0;
}
int main(void) {
  int ok = 1; unsigned long i, na, nb; void *a, *b;''')
    text.append(f'  for (i = 0; i < {len(names)}; i++)')
    text.append('    ok &= same(names[i], sf_index_table[i], sf_index_sizes[i], or_index_table[i], or_index_sizes[i]);')
    for b in blocks:
        o = b.replace('sf_', 'or_', 1)
        text.append(f'  a = {b}(&na); b = {o}(&nb); ok &= same("{b}", a, na, b, nb);')
    text.append('  return !ok;\n}')
    return '\n'.join(text) + '\n'


def forth_check(expected, blocks):
    """A Forth-compiled checker: production bytes against GCC's bytes."""
    text = ['extern const void *const sf_index_table[];', 'extern const unsigned long sf_index_sizes[];']
    text += [f'void *{b}(unsigned long *);' for b in blocks]
    data = []
    for name, hexbytes in expected:
        data.append(','.join(str(int(hexbytes[i:i + 2], 16)) for i in range(0, len(hexbytes), 2)) or '0')
    for i, d in enumerate(data):
        text.append(f'static const unsigned char expect_{i}[] = {{{d}}};')
    text.append('static const unsigned char *const expect[] = {' +
                ','.join(f'expect_{i}' for i in range(len(data))) + '};')
    text.append('static const unsigned long length[] = {' +
                ','.join(str(len(h) // 2) for _, h in expected) + '};')
    text.append('''static int differ(const unsigned char *a, unsigned long na, unsigned long i) {
  unsigned long j;
  if (na != length[i]) return 1;
  for (j = 0; j < na; j++) if (a[j] != expect[i][j]) return 1;
  return 0;
}
int main(void) {
  unsigned long i, n; const unsigned char *a;''')
    objects = len(expected) - len(blocks)
    text.append(f'  for (i = 0; i < {objects}; i++)')
    text.append('    if (differ(sf_index_table[i], sf_index_sizes[i], i)) return 1;')
    for k, b in enumerate(blocks):
        text.append(f'  a = {b}(&n); if (differ(a, n, {objects + k})) return 1;')
    text.append('  return 0;\n}')
    return '\n'.join(text) + '\n'


REJECTS = {
    'divide-by-zero': ('double x = 1.0 / 0.0;', 124, b'error 124'),
    'divide-by-negative-zero': ('float x = 1.0f / -0.0f;', 124, b'error 124'),
    'arithmetic-overflow': ('double x = 1e308 * 10;', 248, b'cc-f64-literal: overflow'),
    'float-overflow': ('float x = 3e38f * 2;', 248, b'cc-f64-literal: overflow'),
    'narrowing-overflow': ('float x = 1e39;', 248, b'cc-f64-literal: overflow'),
    'integer-range': ('int x = 2147483648.0;', 242, b'error 242'),
    'unsigned-negative': ('unsigned x = -1.0;', 242, b'error 242'),
    'byte-range': ('unsigned char x = 256.0;', 242, b'error 242'),
    'long-range': ('long x = 9223372036854775808.0;', 242, b'error 242'),
    'cast-range': ('int x = (char)200.5;', 242, b'error 242'),
    'floating-remainder': ('double x = 5.0 % 2;', 240, b'error 240'),
    'floating-shift': ('double x = 1.0 << 2;', 240, b'error 240'),
    'floating-complement': ('double x = ~1.0;', 240, b'error 240'),
    'floating-to-pointer': ('char *p = 1.0;', 240, b'error 240'),
    'pointer-to-floating': ('double x = (double)(char *)0;', 240, b'error 240'),
    'address-as-double': ('int y; double x = (long)&y;', 232, b'error 232'),
    'floating-array-bound': ('int a[2.0];', 240, b'error 240'),
    'floating-case': ('int f(int x){switch(x){case 1.0:return 1;}return 0;}', 240, b'error 240'),
    'hexadecimal-floating': ('double x = 0x1p0;', 248, b'cc-f64-literal: hexfloat-unsupported'),
    'hexadecimal-float-suffix': ('float x = 0x1.f;', 248, b'cc-f64-literal: hexfloat-unsupported'),
    'double-suffix': ('float x = 1.0ff;', 248, b'cc-f64-literal: suffix-unsupported'),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--work', type=Path)
    ap.add_argument('--generated', type=int, default=400)
    a = ap.parse_args()
    resource.setrlimit(resource.RLIMIT_AS, (1 << 30, 1 << 30))
    w = (a.work or Path(tempfile.mkdtemp(prefix='static-float-'))).resolve()
    w.mkdir(parents=True, exist_ok=True)
    inputs = [ROOT / 'seed-forth', ROOT / '010-lib.fth', *sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),
              CC, FIXTURE, Path(__file__).resolve()]
    hashes = {str(p.relative_to(ROOT)): sha(p) for p in inputs if p.is_file()}

    for name, body in {"long-double-static": "long double x=1.0;", "long-double-suffix": "double x=1.0L;"}.items():
        source = w / (name + ".c")
        source.write_text(body + "\n")
        run([CC, "-c", source, "-o", w / (name + ".o")])
    generated = Generator(0x5F10A7).cases(a.generated)
    body = FIXTURE.read_text() + '\n/* Generated by static-float-check.py. */\n' + '\n'.join(generated) + '\n'
    names = OBJECT.findall(body)
    blocks = BLOCK.findall(body)
    assert len(names) == len(set(names)) and len(names) > a.generated + 100, len(names)
    source = body + table(names, blocks)
    production = w / 'production.c'
    production.write_text(source)
    (w / 'oracle.c').write_text(source.replace('sf_', 'or_'))
    (w / 'harness.c').write_text(harness(names, blocks))

    obj = w / 'production.o'
    run([CC, '-c', production, '-o', obj])
    flags = ['-std=c99', '-w', '-fno-fast-math', '-ffp-contract=off', '-fno-pie', '-no-pie']
    run(['gcc', *flags, '-c', w / 'oracle.c', '-o', w / 'oracle.o'])
    exe = w / 'compare'
    run(['gcc', *flags, w / 'harness.c', w / 'oracle.o', obj, '-o', exe])
    output = run([exe]).stdout.decode().split('\n')
    expected = [line.partition(' ')[::2] for line in output if line]
    assert [n for n, _ in expected] == names + blocks, 'harness order'
    print(f'PASS: {len(names)} static objects and {len(blocks)} block statics '
          f'({len(generated)} generated) match host GCC bytes', flush=True)

    (w / 'forth-check.c').write_text(forth_check(expected, blocks))
    forth_exe = w / 'forth-only'
    run([CC, obj, w / 'forth-check.c', '-o', forth_exe])
    run([forth_exe])
    print('PASS: Forth-only link reproduces the oracle bytes through the seed runtime', flush=True)

    rejections = {}
    for name, (text, status, message) in REJECTS.items():
        src = w / (name + '.c'); src.write_text(text + '\n'); out = w / (name + '.o')
        for existing in (False, True):
            out.unlink(missing_ok=True)
            if existing:
                out.write_bytes(b'previous-object\x00\xff')
            p = run([CC, '-c', src, '-o', out], status)
            assert message in p.stderr, (name, p.stderr)
            if existing:
                assert out.read_bytes() == b'previous-object\x00\xff', name
            else:
                assert not out.exists(), name
        rejections[name] = status
    print(f'PASS: {len(REJECTS)} invalid or unsupported static floating forms reject explicitly', flush=True)

    # The mapped (non-object) System V route runs static initializers as
    # code before main and keeps its binary32/binary64 boundary.
    mapped = w / 'mapped.c'; mapped.write_text('double x = 1.0;\nint main(void){return 0;}\n')
    p = run([TEST / 'sysv-compile.sh', mapped, w / 'mapped'], 232)
    print('PASS: mapped-mode static floating initializer keeps error 232', flush=True)

    assert hashes == {str(p.relative_to(ROOT)): sha(p) for p in inputs if p.is_file()}, 'inputs changed'
    report = {'inputs_sha256': hashes, 'objects': len(names), 'block_statics': len(blocks),
              'generated': len(generated), 'production_object_sha256': sha(obj),
              'source_sha256': sha(production), 'rejections': rejections}
    (w / 'report.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(w / 'report.json')


if __name__ == '__main__':
    main()
