#!/usr/bin/env python3
"""Serial Forth calendar production, source-derived libcpp checks and host oracles."""
from pathlib import Path
import argparse, hashlib, json, os, random, resource, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--gcc-source', type=Path)
args = parser.parse_args()
(ROOT/'build-out').mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix='calendar-', dir=ROOT/'build-out'))
ENV = dict(os.environ, TZ='UTC0', LC_ALL='C')
CC = [sys.executable, ROOT/'tools/gcc-direct-cc.py']
commands = []
def cap():
    resource.setrlimit(resource.RLIMIT_AS, (1024**3, 1024**3))
def run(command, env=ENV):
    p = subprocess.run(list(map(str, command)), env=env, capture_output=True,
                       timeout=180, preexec_fn=cap)
    commands.append({'arguments':list(map(str,command)), 'TZ':env.get('TZ'),
                     'returncode':p.returncode,'stdout':p.stdout.decode(errors='replace'),
                     'stderr':p.stderr.decode(errors='replace')})
    (OUT/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    assert p.returncode == 0 and not p.stderr, (command,p.returncode,p.stdout,p.stderr)
    return p.stdout

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
identity = run(CC+['--print-source-hash']).decode().strip()
seed = digest(ROOT/'seed-forth')
assert (ROOT/'seed-forth').stat().st_size == 1772
for name in ('calendar-check','calendar-fault-check'):
    run(CC+[ROOT/'tests/gcc'/f'{name}.c','-o',OUT/name])
assert run([OUT/'calendar-check','live']) == b'live wall-clock checks passed\n'
assert run([OUT/'calendar-fault-check']) == b'calendar fault checks passed\n'

def leap(y): return y%4==0 and (y%100!=0 or y%400==0)
def jan1(y):
    p=y-1
    return 365*p+p//4-p//100+p//400-719162
loyear, hiyear = -(2**31)+1900, 2**31-1+1900
minimum, maximum = jan1(loyear)*86400, jan1(hiyear+1)*86400-1

def expected(stamp):
    if stamp < minimum or stamp > maximum: return 'error 75'
    days, second = divmod(stamp,86400)
    low, high = loyear, hiyear+1
    while low+1<high:
        middle=(low+high)//2
        if jan1(middle)<=days: low=middle
        else: high=middle
    year=low;day=days-jan1(year);yday=day;month=0
    months=[31,28+leap(year),31,30,31,30,31,31,30,31,30,31]
    while day>=months[month]: day-=months[month];month+=1
    return ' '.join(map(str,[second%60,(second//60)%60,second//3600,day+1,
                             month,year-1900,(days+4)%7,yday,0,71]))
values={-2**63,2**63-1,-1,0,1,-86401,-86400,-86399,86399,86400,
        2**31-1,2**31,2**31+1,minimum-1,minimum,minimum+1,maximum-1,maximum,maximum+1}
# Complete day coverage over selected positive/negative leap-century boundaries.
for year in (-400,-100,-4,-1,0,1,4,100,400,1600,1900,1969,1970,1999,2000,2038,2100,2400):
    start=jan1(year)*86400
    for day in range(366 if leap(year) else 365):
        values.add(start+day*86400)
        if day in (0,30,31,58,59,60,364,365): values.add(start+day*86400+86399)
rng=random.Random(944765)
for unused in range(1024): values.add(rng.randint(minimum,maximum))
for year in range(-800,2801,100):
    start=jan1(year)*86400
    values.update((start-1,start,start+1))
values=sorted(values)
answers=[expected(v) for v in values]
(OUT/'vectors.json').write_text(json.dumps({'minimum':minimum,'maximum':maximum,
                                          'timestamps':values,'expected':answers},indent=2)+'\n')
def exercise(binary, strict_errno=True):
    result=[]
    for start in range(0,len(values),256):
        result += run([binary]+list(map(str,values[start:start+256]))).decode().splitlines()
    if not strict_errno:
        result=[line if line.startswith('error ') else line.rsplit(' ',1)[0]+' 71' for line in result]
    assert result==answers, next(((v,a,b) for v,a,b in zip(values,answers,result) if a!=b), 'length')
exercise(OUT/'calendar-check')
# Unset, empty, ':'-prefixed and unparsable zones mean UTC (no zoneinfo file
# or /etc/localtime is read); POSIX strings are honoured. Wider zone coverage
# is the glibc-differential calendar-tz-check.py.
utc_epoch=b'0 0 0 1 0 70 4 0 0 71\n'
for zone,answer in ((None,utc_epoch),('',utc_epoch),('UTC',utc_epoch),('GMT',utc_epoch),
                    ('GMT0',utc_epoch),('America/New_York',utc_epoch),(':UTC0',utc_epoch),
                    ('UTC0 ',utc_epoch),('UTC0DST',utc_epoch),
                    ('UTC1',b'0 0 23 31 11 69 3 364 0 71\n'),
                    ('EST5EDT,M3.2.0,M11.1.0',b'0 0 19 31 11 69 3 364 0 71\n'),
                    ('<+0530>-5:30',b'0 30 5 1 0 70 4 0 0 71\n')):
    env=dict(ENV)
    if zone is None: del env['TZ']
    else: env['TZ']=zone
    assert run([OUT/'calendar-check','0'],env)==answer,(zone,answer)
env=dict(ENV,TZ='EST5EDT,M3.2.0,M11.1.0')
assert run([OUT/'calendar-check','962368496'],env)==b'56 34 8 30 5 100 5 181 1 71\n'
# Header contract and the exact original configure probe bodies.
probes={
 'header-order': '#include <time.h>\n#include <sys/time.h>\n#include <time.h>\n#include <sys/time.h>\nint main(void) { struct timeval v; v.tv_sec=0;v.tv_usec=0;return sizeof(v)!=16; }\n',
 'header-time': '#include <sys/types.h>\n#include <sys/time.h>\n#include <time.h>\n\nint\nmain ()\n{\nif ((struct tm *) 0)\nreturn 0;\n  ;\n  return 0;\n}\n',
 'struct-tm': '#include <sys/types.h>\n#include <time.h>\n\nint\nmain ()\n{\nstruct tm *tp; tp->tm_sec;\n  ;\n  return 0;\n}\n'}
for name,source in probes.items():
    path=OUT/(name+'.c');path.write_text(source)
    run(CC+['-c',path,'-o',OUT/(name+'.o')])
# Independently compiled host consumers read all public ABI fields and call
# the Forth-built calendar object using the host C calling convention.
run(CC+['-c','-Dtime=seed_time','-Dlocaltime=seed_localtime',ROOT/'runtime/gcc-seed/calendar.c','-o',OUT/'calendar-abi-runtime.o'])
run(CC+['-c',ROOT/'tests/gcc/calendar-abi.c','-o',OUT/'calendar-abi.o'])
for opt in ('-O0','-O2'):
    host=OUT/('host-calendar'+opt)
    run(['gcc',opt,'-D_GNU_SOURCE','-DHOST_ORACLE','-std=c90','-pedantic','-fno-builtin',ROOT/'tests/gcc/calendar-check.c','-o',host])
    exercise(host, strict_errno=False)
    assert run([host,'live'])==b'live wall-clock checks passed\n'
    fault=OUT/('host-fault'+opt)
    run(['gcc',opt,'-std=c90','-pedantic','-fno-builtin','-I'+str(ROOT/'runtime/gcc-seed/include'),ROOT/'tests/gcc/calendar-fault-check.c','-o',fault])
    assert run([fault])==b'calendar fault checks passed\n'
    abi=OUT/('host-abi'+opt)
    run(['gcc',opt,'-no-pie','-D_GNU_SOURCE','-std=c90','-pedantic','-fno-builtin',ROOT/'tests/gcc/calendar-abi-host.c',ROOT/'tests/gcc/calendar-abi-host-syscall.c',OUT/'calendar-abi-runtime.o',OUT/'calendar-abi.o','-o',abi])
    for start in range(0,len(values),256):
        assert run([abi]+list(map(str,values[start:start+256])))==b'calendar host ABI checks passed\n'
# The original block is extracted byte-for-byte. Its environment/allocation/
# diagnostics are explicit test shims, not modifications of libcpp production.
macro_report='SKIPPED: --gcc-source not supplied'
if args.gcc_source:
    source=args.gcc_source.resolve();macro=source/'libcpp/macro.c';configure=source/'libcpp/configure'
    assert digest(macro)=='4372ef02fc59e89b70cc6ccc0ecaabb997fb117293ed42856ccab5864d85d743'
    assert digest(configure)=='85ba0e8dea72afc278807d82ea638e89a229c6f2bfba0326b05fb68f339843e3'
    config=configure.read_text()
    for name in ('header-time','struct-tm'): assert probes[name] in config
    text=macro.read_text();start=text.index('static const char * const monthnames[]');end=text.index('\n};',start)+3
    months=text[start:end]+'\n'
    start=text.index('    case BT_DATE:');end=text.index('\n      break;\n    }',start)+len('\n      break;')
    block=text[start:end]
    (OUT/'original-monthnames.inc').write_text(months)
    (OUT/'original-calendar-cases.inc').write_text(block)
    prefix=(ROOT/'tests/gcc/calendar-macro-prefix.c').read_text().replace('/* CALENDAR_SOURCE_INCLUDE */','#include "'+str(ROOT/'runtime/gcc-seed/calendar.c')+'"')
    fixture=prefix+months+'\nstatic const unsigned char *fixture_expand(cpp_reader *pfile,cpp_hashnode *node)\n{\nconst unsigned char *result=NULL;\nswitch(node->value.builtin) {\n'+block+'\n}\nreturn result;\n}\n'+(ROOT/'tests/gcc/calendar-macro-suffix.c').read_text()
    path=OUT/'original-macro-fixture.c';path.write_text(fixture)
    binary=OUT/'original-macro-forth';run(CC+[path,'-o',binary])
    assert run([binary])==b'original libcpp date/time formatting and caching passed\n'
    for opt in ('-O0','-O2'):
        binary=OUT/('original-macro-host'+opt)
        run(['gcc',opt,'-std=c90','-pedantic','-fno-builtin','-I'+str(ROOT/'runtime/gcc-seed/include'),path,'-o',binary])
        assert run([binary])==b'original libcpp date/time formatting and caching passed\n'
    macro_report={'source_commit':'944765863eec87a9f37e297994fd2af960397138',
                  'source_sha256':{'libcpp/macro.c':digest(macro),'libcpp/configure':digest(configure)},
                  'original_cases_sha256':digest(OUT/'original-calendar-cases.inc'),
                  'checks':'valid -1, epoch, leap day, post2038, syscall failure, zoneinfo name as UTC, POSIX DST and offset zones, year overflow, one-time cache, allocation boundary sentinels'}
assert identity==run(CC+['--print-source-hash']).decode().strip()
assert seed==digest(ROOT/'seed-forth')
names=['runtime/gcc-seed/calendar.c','runtime/gcc-seed/include/time.h','runtime/gcc-seed/include/sys/time.h']
names += [str(p.relative_to(ROOT)) for p in sorted((ROOT/'tests/gcc').glob('calendar-*')) if p.is_file()]
report={'compiler_runtime_source_identity':identity,'seed_sha256':seed,'seed_bytes':1772,
        'production':'Forth compiler/linker/runtime only; no host-built production objects',
        'host_oracles':'separate GCC O0/O2 calendar, injected faults and Forth-object ABI consumers',
        'vectors':len(values),'python_oracle':'independent ordinal-day arithmetic and binary-search year',
        'timestamp_minimum':minimum,'timestamp_maximum':maximum,'timezone':'vectors under TZ=UTC0; UTC fallback and POSIX zone spot checks',
        'faults':'all4095 Linux errno values, malformed statuses/nanoseconds, valid timestamp-1, full signed64 time storage, return stored on every path, static-result preservation',
        'live':'32 strict raw CLOCK_REALTIME windows for Forth; 32 libc time windows per host oracle; host clock_gettime windows for Forth-object ABI calls',
        'header_probes':'both orders, repeated includes, original AC_HEADER_TIME and AC_STRUCT_TM source bodies',
        'original_macro':macro_report,'memory_limit_bytes':1024**3,'execution':'serial',
        'source_sha256':{n:digest(ROOT/n) for n in names},
        'artifact_sha256':{p.name:digest(p) for p in OUT.iterdir() if p.is_file()}}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS calendar: Forth production,',len(values),'vectors, fault boundaries and separate GCC O0/O2 oracles')
print(OUT/'report.json')
