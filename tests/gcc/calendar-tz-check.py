#!/usr/bin/env python3
"""glibc-differential gate for TZ rules, mktime, asctime/ctime and strftime.

tests/gcc/calendar-tz-check.c is built once by the Forth compiler/runtime
(production) and once by host GCC against glibc with -DHOST_ORACLE (oracle
only). Both run in "zone" mode under every TZ below and in "format" mode
under four zones; stdout must be byte-identical. The oracle runs with TZDIR
pointing at an empty directory, so glibc parses each TZ value as a POSIX
string instead of opening a zoneinfo file of that name (EST5EDT, for one,
is also a file name) or the default "posixrules" file. Zones this runtime
deliberately treats as UTC (unset, empty, ':'-prefixed, unparsable; glibc
would read /etc/localtime or a zoneinfo file) run the oracle with the TZ
string that means the same thing to glibc. Processes are capped at 1 GiB
of address space and run three at a time.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib, json, os, resource, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'tests/gcc/calendar-tz-check.c'
(ROOT / 'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='calendar-tz-', dir=ROOT / 'build-out'))
EMPTY = OUT / 'empty-tzdir'
EMPTY.mkdir()
LIMIT = 1024 ** 3
BASE = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}

# (label, TZ for this runtime or None for unset, TZ meaning the same to glibc)
ZONES = [
    ('unset', None, 'UTC0'), ('empty', '', 'UTC0'), ('UTC', 'UTC', 'UTC0'),
    ('GMT', 'GMT', 'GMT0'), ('zoneinfo-name', 'Europe/London', 'UTC0'),
    ('colon', ':EST5EDT,M3.2.0,M11.1.0', 'UTC0'), ('name-only', 'EST', 'UTC0'),
    ('digits', '123', 'UTC0'), ('short-quoted', '<AB>5', 'UTC0'),
]
for text in (
        'UTC0', 'GMT0', 'EST5EDT,M3.2.0,M11.1.0', 'EST5EDT', 'EST5EDT,', 'EST5EDT,M3.2.0',
        'CET-1CEST,M3.5.0,M10.5.0/3', '<+0530>-5:30', 'AEST-10AEDT,M10.1.0,M4.1.0/3',
        'NZST-12NZDT,M9.5.0,M4.1.0/3', '<-03>3', '<-03>3<-02>,M3.5.0/-2,M10.5.0/-1',
        'EST5EDT,M3.2.0/-1:30,M11.1.0/26', 'IST-2IDT,M3.4.4/26,M10.5.0',
        '<-04>4<-03>,M9.1.6/24,M4.1.6/24', 'XXX3YYY,J60/2,J300/2', 'AAA-1BBB,J1/0,J365/25',
        'NNN5MMM,59,300', 'NNN5MMM4,0/3,365/1', 'UTC0DST', '<+14>-14', '<-12>12', 'XXX24',
        'XXX-24:59:59YYY25,M1.1.0,M12.5.6/167', 'EST+5EDT+4,M3.2.0/2:00:00,M11.1.0/2:00:00',
        'WART4WARST,J1/0,J365/25', '<GMT+3>3', 'MMM3:30:15NNN2:15,M4.5.6/23:59:59,M10.1.1/0:0:1',
        '<+1030>-10:30<+11>-11,M10.1.0,M4.1.0', 'EST5EDT,M3.2.0,M11.1.0/2junk',
        'PST8PDT,M3.2.0,M11.1.0', 'MST7', 'HST10', 'EET-2EEST,M3.5.0/3,M10.5.0/4',
        '<+00>0<+02>-2,M3.5.0/1,M10.5.0/3', 'ABC+0', 'ABC-0:00:01', '<A-B>-1<C+D>,J60,J61',
        'AAA0BBB,J59/23:59:59,J60/0', 'AAA0BBB,0/0,365/24', 'AAA-5BBB,M2.5.0/-167,M11.5.6/167',
        'SSS-3TTT-2:30,M12.1.0/0,M1.5.6/23', 'abc5def,M3.2.0/ 2,M11.1.0/+3',
        'Abcdefghijklmnopqrstuvwxyz-1'):
    ZONES.append((text, text, text))
FORMAT_ZONES = ['UTC0', 'EST5EDT,M3.2.0,M11.1.0', '<+0530>-5:30', 'NZST-12NZDT,M9.5.0,M4.1.0/3']
commands = []


def cap():
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT, LIMIT))


def run(command, env=None):
    p = subprocess.run(list(map(str, command)), env=env or dict(os.environ), capture_output=True,
                       timeout=900, preexec_fn=cap)
    commands.append({'arguments': list(map(str, command)),
                     'TZ': None if env is None else env.get('TZ'),
                     'returncode': p.returncode, 'stderr': p.stderr.decode(errors='replace')})
    if p.returncode != 0 or p.stderr:
        raise SystemExit(f'{command}: status {p.returncode}\n{p.stderr.decode(errors="replace")}')
    return p.stdout


def digest(data):
    return hashlib.sha256(data).hexdigest()


forth = OUT / 'calendar-tz-forth'
oracle = OUT / 'calendar-tz-glibc'
run([sys.executable, ROOT / 'tools/gcc-direct-cc.py', SOURCE, '-o', forth])
run(['gcc', '-O2', '-std=c99', '-D_GNU_SOURCE', '-DHOST_ORACLE', '-fno-builtin', '-Wall',
     '-Werror', SOURCE, '-o', oracle])
# The empty TZDIR really makes glibc parse a zoneinfo-file name as POSIX.
probe = run([oracle, 'zone'], dict(BASE, TZ='EST5EDT', TZDIR=str(EMPTY))).split(b'\n', 1)[0]
if probe != b'tzname [EST] [EDT] timezone 18000 daylight 1':
    raise SystemExit(f'oracle TZDIR probe: {probe!r}')


def compare(job):
    mode, label, ours, theirs = job
    env = dict(BASE)
    if ours is not None:
        env['TZ'] = ours
    a = run([forth, mode], env)
    b = run([oracle, mode], dict(BASE, TZ=theirs, TZDIR=str(EMPTY)))
    if a != b:
        al, bl = a.splitlines(), b.splitlines()
        first = next(((n, x, y) for n, (x, y) in enumerate(zip(al, bl), 1) if x != y),
                      ('length', len(al), len(bl)))
        (OUT / f'mismatch-{mode}.forth').write_bytes(a)
        (OUT / f'mismatch-{mode}.glibc').write_bytes(b)
        raise SystemExit(f'{mode} {label!r}: first difference {first}')
    trailer = a.rsplit(b'\n', 2)[-2]
    if not trailer.startswith(b'lines ') or int(trailer[6:]) + 1 != a.count(b'\n'):
        raise SystemExit(f'{mode} {label!r}: bad trailer {trailer!r}')
    return {'mode': mode, 'label': label, 'TZ': ours, 'oracle_TZ': theirs,
            'lines': a.count(b'\n'), 'sha256': digest(a)}


jobs = [('zone', label, ours, theirs) for label, ours, theirs in ZONES]
jobs += [('format', zone, zone, zone) for zone in FORMAT_ZONES]
with ThreadPoolExecutor(max_workers=3) as pool:
    results = list(pool.map(compare, jobs))
total = sum(r['lines'] for r in results)
if total < 100000:
    raise SystemExit(f'only {total} lines compared')
names = ['runtime/gcc-seed/calendar.c', 'runtime/gcc-seed/strftime.c',
         'runtime/gcc-seed/include/time.h', 'tests/gcc/calendar-tz-check.c',
         'tests/gcc/calendar-tz-check.py']
glibc = subprocess.run(['ldd', '--version'], capture_output=True, text=True).stdout.split('\n')[0]
report = {'production': 'Forth compiler/linker/runtime only',
          'oracle': 'host GCC -O2 against glibc, TZDIR=empty directory', 'oracle_libc': glibc,
          'lines_compared': total, 'runs': results, 'memory_limit_bytes': LIMIT,
          'source_sha256': {n: digest((ROOT / n).read_bytes()) for n in names},
          'artifact_sha256': {p.name: digest(p.read_bytes()) for p in (forth, oracle)},
          'commands': commands}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(f'PASS calendar-tz: {total} lines identical to glibc over {len(ZONES)} zones '
      f'and {len(FORMAT_ZONES)} strftime runs')
print(OUT / 'report.json')
