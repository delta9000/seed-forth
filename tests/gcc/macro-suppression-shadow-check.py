#!/usr/bin/env python3
"""Serial low-level suppression-shadow proof, with bounded child processes.

Faults replace only the workspace syscall dispatch. Every emitted test object
still comes from the unchanged seed compiler; no oracle supplies target bytes.
"""
from pathlib import Path
import hashlib, json, os, resource, signal, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[2]
WORK = Path(tempfile.mkdtemp(prefix='macro-shadow-', dir=ROOT/'build-out'))
NAMES = ['010-lib.fth'] + [p.name for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')) if p.name != '120-cc-main.fth']
BASE = b'\n'.join((ROOT/n).read_bytes() for n in NAMES)
PREFIX = b'\n[lit] 77 cc-src-line ! : assert 0= if, [lit] 99 die then, ;\n'
records = []
def run(command, data=None):
    def cap():
        resource.setrlimit(resource.RLIMIT_AS, (1024**3, 1024**3))
        resource.setrlimit(resource.RLIMIT_CPU, (90, 90))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    p = subprocess.Popen(list(map(str, command)), cwd=ROOT, stdin=subprocess.PIPE if data is not None else subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True, preexec_fn=cap)
    try: out, err = p.communicate(data, timeout=120)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL); p.communicate(); raise
    return p.returncode, out, err

def forth(name, body, status=0):
    data = BASE + PREFIX + body.encode() + b'\nbye\n'
    result = run([ROOT/'seed-forth'], data)
    expected = (status, b'', f'cc: line 77: error {status}\n'.encode() if status else b'')
    (WORK/(name+'.fth')).write_bytes(PREFIX + body.encode() + b'\nbye\n')
    (WORK/(name+'.stderr')).write_bytes(result[2])
    assert result == expected, (name, result, expected)
    records.append({'case': name, 'exit_status': status, 'status': 'PASS'})
    (WORK/'report.json').write_text(json.dumps({'status':'in-progress','cases':records}, indent=2)+'\n')
    print('PASS', name, flush=True)

setup = '''cc-io-direct-workspace true cc-prep-direct !
cc-src-buf cc-pp-out ! cc-src-cap cc-pp-out-cap ! [lit] 36 cc-pp-out-code !
cc-pp-flags-init
'''
forth('default-no-map', '''
: unexpected-map drop [lit] 99 die ; ' unexpected-map is cc-workspace-syscall-fwd
cc-src-buf cc-pp-out ! cc-pp-flags-init
cc-pp-flags-base @ 0= assert cc-pp-out-flags @ 0= assert
cc-pp-scratch cc-pp-flag-address 0= assert cc-src-buf cc-pp-flag-address 0= assert
''')
forth('allocation-layout-cache', '''
cc-io-direct-workspace true cc-prep-direct ! variable calls
: counted-map [lit] 1 calls +! dup [lit] 5242880 = assert cc-workspace-syscall ;
' counted-map is cc-workspace-syscall-fwd
cc-src-buf cc-pp-out ! cc-pp-flags-init
cc-pp-flags-base @ [lit] 0 > assert calls @ [lit] 1 = assert
cc-pp-out-flags @ cc-pp-flags-base @ - [lit] 2097152 = assert
cc-pp-flags-base @ cc-pp-flags-init cc-pp-flags-base @ = assert calls @ [lit] 1 = assert
''')
for label, addr, expr in [
    ('scratch-first','cc-pp-scratch','cc-pp-flags-base @'),
    ('scratch-last','cc-pp-scratch cc-pp-scratch-cap + 1-','cc-pp-flags-base @ cc-pp-scratch-cap + 1-'),
    ('scratch-before','cc-pp-scratch 1-','[lit] 0'),
    ('scratch-onepast','cc-pp-scratch cc-pp-scratch-cap +','[lit] 0'),
    ('source-first','cc-src-buf','cc-pp-flags-base @ cc-pp-scratch-cap +'),
    ('source-last','cc-src-buf cc-src-cap + 1-','cc-pp-flags-base @ [lit] 5242880 + 1-'),
    ('source-before','cc-src-buf 1-','[lit] 0'),
    ('source-onepast','cc-src-buf cc-src-cap +','[lit] 0'),
    ('raw','cc-in-buf','[lit] 0'), ('macro-pool','cc-macro-pool','[lit] 0')]:
    forth('address-'+label, setup+f'{addr} cc-pp-flag-address {expr} = assert')
forth('native-default-source-layout', '''true cc-prep-direct ! cc-src-buf cc-pp-out ! cc-pp-flags-init
cc-src-cap [lit] 2097152 = assert
cc-src-buf cc-src-cap + 1- cc-pp-flag-address cc-pp-flags-base @ [lit] 4194304 + 1- = assert
cc-src-buf cc-src-cap + cc-pp-flag-address 0= assert
''')
forth('source-capacity-over-shadow', 'true cc-prep-direct ! cc-src-direct-cap 1+ cc-src-limit ! cc-pp-flags-init', 43)
for name, value in [('zero','[lit] 0'),('enomem','[lit] 0 [lit] 12 -'),('eperm','[lit] 0 [lit] 1 -'),('last-linux-errno','[lit] 0 [lit] 4095 -')]:
    forth('kernel-map-'+name, f'true cc-prep-direct ! : fail-map drop {value} ; \' fail-map is cc-workspace-syscall-fwd cc-pp-flags-init',43)
forth('direct-default-direct-selection', setup+'''
cc-pp-flags-base @
[lit] 0 cc-prep-direct ! cc-pp-flags-init cc-pp-out-flags @ 0= assert
cc-pp-scratch cc-pp-unavailable? 0= assert
true cc-prep-direct ! cc-pp-flags-init cc-pp-flags-base @ = assert
cc-pp-out-flags @ cc-pp-flags-base @ cc-pp-scratch-cap + = assert
''')
forth('nested-sink-selection', setup+'''
cc-pp-out-flags @
cc-pp-scratch [lit] 0 cc-pp-temp-cap [lit] 37 cc-pp-sink-push
cc-pp-out-flags @ cc-pp-flags-base @ = assert
cc-macro-pool [lit] 0 cc-macro-pool-cap [lit] 35 cc-pp-sink-push
cc-pp-out-flags @ 0= assert
cc-pp-sink-pop cc-pp-out-flags @ cc-pp-flags-base @ = assert
cc-pp-sink-pop cc-pp-out-flags @ = assert cc-pp-sink-depth @ 0= assert
''')
for name, buffer, cap, code in [('scratch','cc-pp-scratch','cc-pp-scratch-cap',43),('source','cc-src-buf','cc-src-cap',36)]:
    body = setup + f'''{buffer} [lit] 0 {cap} [lit] {code} cc-pp-sink-push
{cap} 1- cc-pp-out-pos !
[lit] 90 cc-pp-out-flags @ {cap} + 1- c!
[lit] 65 cc-prep-emit-byte
cc-pp-out-pos @ {cap} = assert
{buffer} {cap} + 1- c@ [lit] 65 = assert
cc-pp-out-flags @ {cap} + 1- c@ 0= assert
'''
    forth(name+'-exact-last-byte',body)
    forth(name+'-onepast-rejected',body+'[lit] 66 cc-prep-emit-byte',code)
forth('fresh-write-clears-stale',setup+'''
true cc-pp-out-flags @ c! [lit] 65 cc-prep-emit-byte
cc-pp-out-flags @ c@ 0= assert cc-src-buf c@ [lit] 65 = assert
''')
forth('same-address-copy-preserves',setup+'''
[lit] 65 cc-src-buf c! true cc-pp-out-flags @ c!
cc-src-buf cc-pp-copy-marked-byte cc-pp-out-flags @ c@ 0= 0= assert
cc-src-buf c@ [lit] 65 = assert
''')
forth('cross-buffer-copy-preserves',setup+'''
[lit] 65 cc-pp-scratch c! true cc-pp-flags-base @ c!
cc-pp-scratch [lit] 1 cc-pp-emit-bytes
cc-pp-out-flags @ c@ 0= 0= assert cc-src-buf c@ [lit] 65 = assert
''')
forth('unmarked-copy-clears-stale',setup+'''
[lit] 65 cc-macro-pool c! true cc-pp-out-flags @ c!
cc-macro-pool [lit] 1 cc-pp-emit-bytes
cc-pp-out-flags @ c@ 0= assert cc-src-buf c@ [lit] 65 = assert
''')
forth('scratch-reuse-clears-only-active',setup+'''
cc-pp-scratch cc-pp-scratch-top ! cc-pp-temp-begin
true cc-pp-out-flags @ c! true cc-pp-out-flags @ 1+ c!
[lit] 65 cc-prep-emit-byte cc-pp-temp-end 2drop
cc-pp-scratch cc-pp-scratch-top ! cc-pp-temp-begin [lit] 66 cc-prep-emit-byte
cc-pp-out-flags @ c@ 0= assert cc-pp-out-flags @ 1+ c@ 0= 0= assert
cc-pp-temp-end 2drop
''')
forth('preprocess-reset-lazy-clearing',setup+'''
[lit] 0 cc-in-len ! cc-preprocess
true cc-pp-out-flags @ c! [lit] 1 cc-pp-out-pos !
cc-preprocess cc-pp-out-pos @ 0= assert cc-pp-sink-depth @ 0= assert
cc-pp-scratch-top @ cc-pp-scratch = assert
[lit] 65 cc-prep-emit-byte cc-pp-out-flags @ c@ 0= assert
''')
# Negative controls execute mutated in-memory vocabularies, never edited sources.
# Each specifically violates an asserted invariant and must exit via assert/99.
mutations = [
 ('fresh-clear', b'  cc-pp-out-flags @ if, [lit] 0 cc-pp-out-flags @ cc-pp-out-pos @ + c! then,\n', b'',
  setup+'true cc-pp-out-flags @ c! [lit] 65 cc-prep-emit-byte cc-pp-out-flags @ c@ 0= assert'),
 ('copy-mark', b'    true cc-pp-out-flags @ cc-pp-out-pos @ + 1- c!\n', b'',
  setup+'[lit] 65 cc-pp-scratch c! true cc-pp-flags-base @ c! cc-pp-scratch [lit] 1 cc-pp-emit-bytes cc-pp-out-flags @ c@ 0= 0= assert'),
 ('scratch-exclusive-end', b'over cc-pp-scratch cc-pp-scratch-cap + < and if,', b'over cc-pp-scratch cc-pp-scratch-cap + <= and if,',
  setup+'cc-pp-scratch cc-pp-scratch-cap + cc-pp-flag-address 0= assert'),
 ('source-exclusive-end', b'over cc-src-buf cc-src-cap + < and if,', b'over cc-src-buf cc-src-cap + <= and if,',
  setup+'cc-src-buf cc-src-cap + cc-pp-flag-address 0= assert'),
]
for name, old, new, body in mutations:
    assert BASE.count(old)==1,name
    changed=BASE.replace(old,new)
    result=run([ROOT/'seed-forth'],changed+PREFIX+body.encode()+b'\nbye\n')
    assert result==(99,b'',b''),(name,result)
    records.append({'case':'mutation-'+name,'status':'detected','exit_status':99,
                    'mutated_vocabulary_sha256':hashlib.sha256(changed).hexdigest()})
    print('PASS mutation detected',name,flush=True)
# All failure paths run before the actual object publisher, and retain absent or
# existing destinations. The direct driver writes preprocessing output only on success.
source = WORK/'failure.c'; source.write_text('int answer(void) { return 42; }\n')
for fault, suffix, code in [('allocation', '.o',43), ('paste', '.o',47), ('paste', '.i',47)]:
    for present in (False, True):
        name=f'publication-{fault}-{suffix[1:]}-'+('existing' if present else 'absent')
        dest=WORK/(name+suffix); old=b'previous complete output\n'
        if present: dest.write_bytes(old)
        if fault == 'allocation':
            driver=f'''\ncreate destination s, {dest} [lit] 0 c,
cc-sysv-object-enable [lit] 67108864 cc-arena-map
cc-io-direct-workspace cc-prep-direct-workspace cc-om-direct-workspace
cc-label-direct-workspace cc-obj-direct-workspace cc-gfixup-direct-workspace
: fail-map drop [lit] 0 [lit] 12 - ; ' fail-map is cc-workspace-syscall-fwd
: test cc-load-stdin cc-preprocess cc-sysv-object-program destination cc-obj-write bye ;
test\n'''.encode()
            result=run([ROOT/'seed-forth'],BASE+driver+source.read_bytes())
        else:
            bad=WORK/(name+'.c');bad.write_text('#define A A\n#define P(x,y) x##y\n#define I(x) P(x,B)\nint I(A);\n')
            result=run(['python3',ROOT/'tools/gcc-direct-cc.py','-c' if suffix=='.o' else '-E',bad,'-o',dest])
        assert result[0] == code and f'error {code}'.encode() in result[2], (name,result)
        assert dest.exists() == present and (not present or dest.read_bytes()==old),name
        assert not list(WORK.glob(dest.name+'.obj-*')),name
        records.append({'case':name,'exit_status':code,'status':'PASS','previous_output_preserved':present})
        print('PASS',name,flush=True)
(WORK/'report.json').write_text(json.dumps({'status':'PASS','cases':records,'source_sha256':hashlib.sha256((ROOT/'040-cc-prep.fth').read_bytes()).hexdigest(),'memory_limit_bytes':1024**3},indent=2)+'\n')
print('PASS',len(records),'shadow/publication cases:',WORK/'report.json')
