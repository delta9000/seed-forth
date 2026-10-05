#!/usr/bin/env python3
"""Records with hundreds of members: Forth production and host ABI oracles.

A generated 200-member struct mixes every integer width, signed and unsigned
bitfields, byte arrays, nested structs, unions and pointers.  Its sizeof,
offsetof, static and automatic initializers, copies, by-value arguments and
returns run in Forth-only, host -O0/-O2 and both mixed-ABI programs, which
must all print the same bytes.  A 300-member struct with floating members
(assigned at run time: floating aggregate initializers are a separate gap)
and a 260-member union check layout and copies.  The member cap is C99's
1023 (5.2.4.1): exactly 1023 members compile, including flattened anonymous
members, and the 1024th is rejected with error 50 without publishing output.
"""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[2]
CAP = 1023
NAMES = '"alpha", "beta", "gamma", "delta", "eps"'


def big_members():
    """(declaration, kind, name, width) for the 200-member struct."""
    out = []
    for i in range(200):
        k = i % 10
        if k == 0: out.append((f'signed char c{i};', 'int', f'c{i}', 0))
        elif k == 1: out.append((f'short s{i};', 'int', f's{i}', 0))
        elif k == 2: out.append((f'int i{i};', 'int', f'i{i}', 0))
        elif k == 3:
            t = 'long' if i % 20 == 3 else 'unsigned long long'
            out.append((f'{t} l{i};', 'int', f'l{i}', 0))
        elif k == 4:
            w = 1 + i % 13
            out.append((f'unsigned u{i} : {w};', 'ubit', f'u{i}', w))
        elif k == 5:
            w = 2 + i % 9
            out.append((f'int b{i} : {w};', 'sbit', f'b{i}', w))
        elif k == 6: out.append((f'unsigned char a{i}[3];', 'array', f'a{i}', 0))
        elif k == 7: out.append((f'struct inner n{i};', 'inner', f'n{i}', 0))
        elif k == 8: out.append((f'union mix m{i};', 'union', f'm{i}', 0))
        else: out.append((f'const char *p{i};', 'ptr', f'p{i}', 0))
    return out


def value(i, seed):
    return (seed * 131 + i * 7) % 97 - 40


def init_item(member, i, seed):
    _, kind, _, w = member
    v = value(i, seed)
    if kind == 'ubit': return str(v % (1 << w))
    if kind == 'sbit':
        m = 1 << (w - 1)
        return str(v % m - m // 2)
    if kind == 'array': return '{%d, %d, %d}' % (v % 256, (v + 1) % 256, (v + 2) % 256)
    if kind == 'inner': return '{%d, %dL, %d}' % (v, v * 1000, v % 100)
    if kind == 'union': return '{%d}' % v
    if kind == 'ptr': return NAMES.split(', ')[i % 5]
    return str(v)


def header():
    lines = ['struct inner { short x; long y; char z; };',
             'union mix { int v; char bytes[6]; };',
             'struct big {']
    lines += ['  ' + m[0] for m in big_members()]
    lines += ['};', 'extern const char *names[5];',
              'struct big make(int seed);',
              'unsigned long digest(struct big b);',
              'void fill(struct big *p, int seed);', '']
    return '\n'.join(lines)


def provider():
    body = ['#include "large-record.h"',
            f'const char *names[5] = {{{NAMES}}};',
            'void fill(struct big *p, int seed)', '{']
    for i, (_, kind, name, w) in enumerate(big_members()):
        v = f'((seed * 131 + {i * 7}) % 97 - 40)'
        if kind == 'ubit': body.append(f'  p->{name} = (unsigned)({v} + 97) % {1 << w}u;')
        elif kind == 'sbit':
            m = 1 << (w - 1)
            body.append(f'  p->{name} = ({v} + 97) % {m} - {m // 2};')
        elif kind == 'array':
            body.append(f'  p->{name}[0] = {v}; p->{name}[1] = {v} + 1; p->{name}[2] = {v} + 2;')
        elif kind == 'inner':
            body.append(f'  p->{name}.x = {v}; p->{name}.y = {v} * 1000L; p->{name}.z = {v} % 100;')
        elif kind == 'union': body.append(f'  p->{name}.v = {v};')
        elif kind == 'ptr': body.append(f'  p->{name} = names[{i % 5}];')
        else: body.append(f'  p->{name} = {v};')
    body += ['}', 'struct big make(int seed)', '{', '  struct big b;',
             '  fill(&b, seed);', '  return b;', '}',
             'unsigned long digest(struct big b)', '{', '  unsigned long h = 17;']
    for _, kind, name, _ in big_members():
        if kind == 'array':
            body.append(f'  h = h * 31 + b.{name}[0] + b.{name}[1] * 3 + b.{name}[2] * 5;')
        elif kind == 'inner':
            body.append(f'  h = h * 31 + (unsigned long)(b.{name}.x + b.{name}.y + b.{name}.z);')
        elif kind == 'union': body.append(f'  h = h * 31 + (unsigned long)b.{name}.v;')
        elif kind == 'ptr': body.append(f'  h = h * 31 + (unsigned long)(b.{name}[0] + b.{name}[1]);')
        else: body.append(f'  h = h * 31 + (unsigned long)b.{name};')
    body += ['  return h;', '}', '']
    return '\n'.join(body)


def main_unit():
    members = big_members()
    items = ', '.join(init_item(m, i, 3) for i, m in enumerate(members))
    auto = ', '.join(init_item(m, i, 5) for i, m in enumerate(members))
    wide = []
    for i in range(300):
        t = ('double', 'float', 'char', 'long', 'short', 'int *')[i % 6]
        wide.append(f'  {t} w{i};')
    many = [f'  {("char", "short", "int", "long", "double")[i % 5]} v{i};' for i in range(259)]
    many.append('  char tail[37];')
    lines = ['#include <stddef.h>', '#include <stdio.h>', '#include "large-record.h"',
             f'static struct big g = {{{items}}};',
             'struct wide {', *wide, '};',
             'static struct wide gw;',
             'union many {', *many, '};',
             'static unsigned long offsets(void)', '{', '  unsigned long h = 0;']
    for _, kind, name, _ in members:
        if kind not in ('ubit', 'sbit'):
            lines.append(f'  h = h * 7 + offsetof(struct big, {name});')
    for i in range(0, 300, 7):
        lines.append(f'  h = h * 7 + offsetof(struct wide, w{i});')
    lines += ['  return h;', '}',
              'int main(void)', '{',
              f'  struct big a = {{{auto}}};',
              '  struct big c, d;', '  struct wide w;', '  union many u;',
              '  int fail = 0;',
              '  printf("sizes %lu %lu %lu %lu\\n", (unsigned long)sizeof(struct big),'
              ' (unsigned long)sizeof(struct wide), (unsigned long)sizeof(union many),'
              ' (unsigned long)offsetof(struct big, p199));',
              '  printf("offsets %lu\\n", offsets());',
              '  printf("static %lu\\n", digest(g));',
              '  printf("automatic %lu\\n", digest(a));',
              '  c = g; c.l193 += 1; c.u194 = 0; c.n197.y = -9;',
              '  fail |= digest(c) == digest(g) || g.l193 == c.l193 || g.n197.y == -9;',
              '  d = make(11);',
              '  printf("returned %lu\\n", digest(d));',
              '  fill(&a, 11);',
              '  fail |= digest(a) != digest(d);',
              '  printf("fields %d %u %d %d %s %d\\n", (int)g.c190, g.u194, g.b195, g.a196[2],'
              ' g.p199, g.m198.v);',
              '  gw.w0 = 1.5; gw.w1 = 2.25; gw.w6 = 6.5; gw.w298 = 4;',
              '  w = gw; w.w299 = &fail; gw.w6 = 0;',
              '  fail |= w.w0 != 1.5 || w.w1 != 2.25 || w.w6 != 6.5 || w.w298 != 4 || w.w299 != &fail;',
              '  u.v258 = -3; fail |= u.v258 != -3;',
              '  u.tail[36] = 9; fail |= u.tail[36] != 9;',
              '  printf("%s\\n", fail ? "FAIL" : "copies independent");',
              '  return fail;', '}', '']
    return '\n'.join(lines)


def members(n, prefix='f'):
    return ' '.join(f'int {prefix}{i};' for i in range(n))


def boundary_source():
    anon = members(CAP - 10) + ' struct { ' + members(10, 'x') + ' };'
    return f'''struct cap {{ {members(CAP)} }};
struct capanon {{ {anon} }};
union capunion {{ {members(CAP)} }};
int main(void)
{{
  static struct cap s;
  static struct capanon t;
  union capunion u;
  s.f{CAP - 1} = 7; t.x9 = 8; u.f{CAP - 1} = 9;
  return sizeof(struct cap) != {4 * CAP} || sizeof(struct capanon) != {4 * CAP}
    || sizeof(union capunion) != 4 || s.f{CAP - 1} != 7 || t.x9 != 8 || u.f0 != 9;
}}
'''


REJECT = {
    'struct-1024': (f'struct s {{ {members(CAP + 1)} }};', 50),
    'union-1024': (f'union u {{ {members(CAP + 1)} }};', 50),
    'anonymous-1024': (f'struct s {{ {members(CAP - 9)} struct {{ {members(10, "x")} }}; }};', 50),
    'bitfield-1024': ('struct s { ' + ' '.join(f'unsigned f{i}:1;' for i in range(CAP + 1)) + ' };', 50),
    # Field qualification is keyed by record address; it must survive the
    # field table moving when it grows past its first 8 records.
    'qualified-after-growth': ('struct S { const int m[2][3]; ' + members(20, 'b')
                               + ' };\nvoid f(struct S *p) { int (*q)[3] = p->m; }', 238),
}


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    (ROOT / 'build-out').mkdir(exist_ok=True)
    work = (args.work or Path(tempfile.mkdtemp(prefix='large-record-', dir=ROOT / 'build-out'))).resolve()
    work.mkdir(parents=True, exist_ok=True)
    events = []
    env = dict(os.environ, LC_ALL='C')

    def run(command, expected=0):
        command = list(map(str, command))
        p = subprocess.run(command, capture_output=True, timeout=300, env=env)
        events.append(dict(command=command, status=p.returncode,
                           stderr=p.stderr.decode(errors='replace')))
        (work / 'commands.json').write_text(json.dumps(events, indent=2) + '\n')
        assert p.returncode == expected, events[-1]
        return p
    cc = [sys.executable, ROOT / 'tools/gcc-direct-cc.py']
    before = run(cc + ['--print-source-hash']).stdout.decode().strip()
    (work / 'large-record.h').write_text(header())
    units = {'provider': provider(), 'main': main_unit()}
    for part, text in units.items(): (work / f'large-record-{part}.c').write_text(text)
    sources = [work / f'large-record-{part}.c' for part in units]
    objects = [work / f'{part}.o' for part in units]
    for source, obj in zip(sources, objects): run(cc + ['-I' + str(work), '-c', source, '-o', obj])
    binary = work / 'forth-only'
    run(cc + objects + ['-o', binary])
    output = run([binary]).stdout
    assert output.endswith(b'copies independent\n'), output
    for opt in ('-O0', '-O2'):
        hosts = [work / f'{part}{opt}.o' for part in units]
        for source, obj in zip(sources, hosts):
            run(['gcc', '-std=gnu89', '-U_FORTIFY_SOURCE', opt, '-fno-pie', '-fno-stack-protector',
                 '-I' + str(work), '-c', source, '-o', obj])
        for name, inputs in [('host', hosts), ('forth-provider', [objects[0], hosts[1]]),
                             ('forth-caller', [hosts[0], objects[1]])]:
            exe = work / (name + opt)
            run(['gcc', '-no-pie', '-Wl,-z,noexecstack', *inputs, '-o', exe])
            assert run([exe]).stdout == output, (name, opt)
    boundary = work / 'cap-boundary.c'
    boundary.write_text(boundary_source())
    run(cc + [boundary, '-o', work / 'cap-boundary']); run([work / 'cap-boundary'])
    for opt in ('-O0', '-O2'):
        run(['gcc', '-std=gnu89', '-U_FORTIFY_SOURCE', opt, boundary, '-o', work / ('cap-boundary' + opt)])
        run([work / ('cap-boundary' + opt)])
    for name, (source, status) in REJECT.items():
        path = work / (name + '.c'); path.write_text(source + '\n')
        obj = work / (name + '.o')
        obj.unlink(missing_ok=True)
        result = run(cc + ['-c', path, '-o', obj], status)
        assert f'error {status}'.encode() in result.stderr and not obj.exists(), name
        original = b'preserve-existing-output\n'; obj.write_bytes(original)
        run(cc + ['-c', path, '-o', obj], status)
        assert obj.read_bytes() == original, name
    assert run(cc + ['--print-source-hash']).stdout.decode().strip() == before
    (work / 'report.json').write_text(json.dumps({
        'source_identity': before, 'member_cap': CAP,
        'output_sha256': hashlib.sha256(output).hexdigest(),
        'oracles': 'host gcc -std=gnu89 -U_FORTIFY_SOURCE O0/O2 and both mixed ABI directions',
        'negative_cases': len(REJECT), 'commands': 'commands.json'}, indent=2) + '\n')
    sys.stdout.write(output.decode())
    print(f'PASS: {CAP}-member records, layout, initializers, copies, by-value ABI and bounded error 50')
    print(work / 'report.json')


if __name__ == '__main__':
    main()
