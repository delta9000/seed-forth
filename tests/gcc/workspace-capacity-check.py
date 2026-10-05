#!/usr/bin/env python3
"""Serial Forth workspace boundary tests. No host-produced target objects."""
from pathlib import Path
import hashlib,json,resource,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
NAMES=['010-lib.fth']+[p.name for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')) if p.name!='120-cc-main.fth']+['141-archive.fth']
BASE=b'\n'.join((ROOT/n).read_bytes() for n in NAMES)
PREFIX=b'\n[lit] 77 cc-src-line ! : assert 0= if, [lit] 99 die then, ;\n'
WORK=Path(tempfile.mkdtemp(prefix='workspace-capacity-',dir=ROOT/'build-out'));records=[]
def forth(name,body,status=0,stdin=b''):
 p=subprocess.run([ROOT/'seed-forth'],input=BASE+PREFIX+body.encode()+(b'' if body.endswith('\n') else b'\n')+stdin,capture_output=True,timeout=30)
 error=f'cc: line 77: error {status}\n'.encode() if status else b''
 assert (p.returncode,p.stdout,p.stderr)==(status,b'',error),(name,p)
 records.append({'case':name,'status':status})
def out(body):return body+'\nbye\n'
# Retain the actual full-load HERE, including linker and archive layers.
p=subprocess.run([ROOT/'seed-forth'],input=BASE+b'\nhere cc-err-dec bye\n',capture_output=True,timeout=30)
assert p.returncode==0 and p.stdout==b'' and p.stderr.isdigit(),p
end=int(p.stderr);assert end<0x1400000
records.append({'case':'full-load-here','address':end,'mapping_start':0x400000,'mapping_end':0x1400000,'headroom':0x1400000-end})
# All compiler libraries, archive and linker load within the unchanged seed map.
forth('full-load-mapping-headroom',out('here [lit] 20971520 < assert cc-in-cap [lit] 1048576 = assert cc-src-cap [lit] 2097152 = assert cc-macro-cap [lit] 4096 = assert cc-om-cap [lit] 4096 = assert cc-prep-inc-cap [lit] 1048576 = assert cc-prep-inc-buf cc-prep-inc-pool = assert cc-obj-section-cap [lit] 262144 = assert'))
# Policy constants: source/include and rodata/data bounds (measured maximum
# plus 25%, rounded up to whole MiB); the other direct bounds are unchanged.
forth('direct-policy-constants',out('cc-in-direct-cap [lit] 3145728 = assert cc-src-direct-cap [lit] 7340032 = assert cc-out-direct-cap [lit] 4194304 = assert cc-prep-inc-direct-cap [lit] 7340032 = assert cc-obj-section-direct-cap [lit] 2097152 = assert cc-obj-text-direct-cap [lit] 4194304 = assert'))
# Rounded request sizes reject sign-bit values and n+4095 wrap before a syscall.
for n,want in [(1,4096),(4095,4096),(4096,4096),(4097,8192),(9223372036854771712,9223372036854771712)]:
 forth('round-'+str(n),out(f'[lit] {n} [lit] 20 cc-workspace-round [lit] {want} = assert'))
for n in [0,9223372036854771713,9223372036854775807,9223372036854775808,18446744073709551615]:
 forth('reject-round-'+str(n),out(f'[lit] {n} [lit] 20 cc-workspace-round drop'),20)
# Failure through the only mmap gate, for each independent workspace.
for name,word,code in [('io','cc-io-direct-workspace',20),('prep','cc-prep-direct-workspace',34),('objects','cc-om-direct-workspace',245),('labels','cc-label-direct-workspace',171),('elf','cc-obj-direct-workspace',245),('global-fixups','cc-gfixup-direct-workspace',81)]:
 forth('mmap-failure-'+name,out(": fail-map drop [lit] 0 [lit] 12 - ; ' fail-map is cc-workspace-syscall-fwd "+word),code)
# The prep selector maps macros first, then the include pool: fail only the
# second request, which must die with the include pool's code 32.
forth('mmap-failure-prep-include-pool',out("variable maps : fail-second [lit] 1 maps +! maps @ [lit] 2 = if, drop [lit] 0 [lit] 12 - else, cc-workspace-syscall then, ; ' fail-second is cc-workspace-syscall-fwd cc-prep-direct-workspace"),32)
forth('prep-mapping-requests',out("variable maps : count-map [lit] 1 maps +! maps @ [lit] 2 = if, dup cc-prep-inc-direct-cap = assert then, cc-workspace-syscall ; ' count-map is cc-workspace-syscall-fwd cc-prep-direct-workspace cc-prep-direct-workspace maps @ [lit] 2 = assert"))
# Cache is per-process, bounded and idempotent. Selection preserves default storage.
forth('mapped-slices-idempotence-defaults',out('''
cc-io-direct-workspace cc-prep-direct-workspace cc-om-direct-workspace cc-label-direct-workspace cc-obj-direct-workspace cc-gfixup-direct-workspace
cc-in-cap cc-in-direct-cap = assert cc-src-cap cc-src-direct-cap = assert
cc-src-buf cc-in-buf - cc-in-cap = assert
cc-out-buf cc-src-buf - cc-src-cap = assert cc-out-cap cc-out-direct-cap = assert
cc-io-direct-base @ cc-in-buf = assert
cc-macro-cap cc-macro-direct-cap = assert cc-om-cap cc-om-direct-cap = assert
cc-prep-inc-cap cc-prep-inc-direct-cap = assert cc-prep-inc-buf cc-prep-inc-direct-base @ = assert
cc-obj-section-cap cc-obj-section-direct-cap = assert
cc-gfixup-slot cc-gfixup-out-pos - cc-gfixup-cap [lit] 8 * = assert
cc-label-name-len cc-label-name-addr - cc-label-cap [lit] 8 * = assert
cc-label-vaddr cc-label-name-len - cc-label-cap [lit] 8 * = assert
cc-label-fixup cc-label-vaddr - cc-label-cap [lit] 8 * = assert
cc-label-switch-depth cc-label-fixup - cc-label-cap [lit] 8 * = assert
cc-obj-relocs cc-obj-payload - cc-obj-direct-payload-bytes = assert
cc-macro-name-len cc-macro-name-addr - cc-macro-cap [lit] 8 * = assert
cc-macro-body-addr cc-macro-name-len - cc-macro-cap [lit] 8 * = assert
cc-macro-body-len cc-macro-body-addr - cc-macro-cap [lit] 8 * = assert
cc-macro-params cc-macro-body-len - cc-macro-cap [lit] 8 * = assert
cc-macro-busy cc-macro-params - cc-macro-cap [lit] 8 * = assert
cc-out-buf cc-label-name-addr cc-obj-payload cc-obj-relocs cc-gfixup-out-pos
cc-in-buf cc-src-buf cc-macro-name-addr cc-om-records cc-prep-inc-buf
cc-io-direct-workspace cc-prep-direct-workspace cc-om-direct-workspace cc-label-direct-workspace cc-obj-direct-workspace cc-gfixup-direct-workspace
cc-prep-inc-buf = assert cc-om-records = assert cc-macro-name-addr = assert cc-src-buf = assert cc-in-buf = assert
cc-gfixup-out-pos = assert cc-obj-relocs = assert cc-obj-payload = assert cc-label-name-addr = assert cc-out-buf = assert
cc-io-default-workspace cc-prep-default-workspace cc-om-default-workspace cc-label-default-workspace cc-obj-default-workspace cc-gfixup-default-workspace
cc-in-buf cc-in-default-buf = assert cc-src-buf cc-src-default-buf = assert
cc-macro-name-addr cc-macro-default-name-addr = assert cc-om-records cc-om-default-records = assert
cc-in-cap cc-in-default-cap = assert cc-src-cap cc-src-default-cap = assert
cc-macro-cap cc-macro-default-cap = assert cc-om-cap cc-om-default-cap = assert
cc-out-cap cc-out-default-cap = assert cc-label-cap cc-label-default-cap = assert
cc-gfixup-cap cc-gfixup-default-cap = assert
cc-prep-inc-buf cc-prep-inc-pool = assert cc-prep-inc-cap [lit] 1048576 = assert
cc-obj-section-cap cc-obj-section-default-cap = assert
cc-obj-text-cap cc-obj-text-default-cap = assert cc-obj-reloc-cap cc-obj-reloc-default-cap = assert
cc-obj-payload cc-obj-default-payload = assert cc-obj-relocs cc-obj-default-relocs = assert
cc-label-name-addr cc-label-default-name-addr = assert cc-gfixup-out-pos cc-gfixup-default-out-pos = assert
'''))
# Isolated exact/one-past checks, with sentinels in the adjacent mapped buffer.
for direct in (False,True):
 setup='cc-io-direct-workspace cc-prep-direct-workspace cc-om-direct-workspace cc-label-direct-workspace cc-obj-direct-workspace cc-gfixup-direct-workspace\n' if direct else ''
 tag='direct' if direct else 'default'
 # Raw read retains its historical one-byte EOF reserve: cap-1 payload fits.
 cap=3145728 if direct else 1048576
 for size,status in [(cap-1,0),(cap,20),(cap+1,20)]:
  body=setup+'[lit] 90 cc-src-buf c!\n'+f': raw-read [lit] 0 cc-in-buf cc-in-cap [lit] 20 cc-read-all [lit] {size} = assert cc-src-buf c@ [lit] 90 = assert bye ; raw-read\n'
  forth(tag+'-raw-'+str(size),body,status,b'x'*size)
 # A source sink may use every byte. Guard verifies writing its last byte.
 sink=setup+'[lit] 90 cc-out-buf c! cc-src-buf cc-pp-out ! cc-src-cap cc-pp-out-cap ! [lit] 36 cc-pp-out-code ! cc-src-cap 1- cc-pp-out-pos ! [lit] 65 cc-prep-emit-byte\n'
 forth(tag+'-source-exact',out(sink+'cc-src-buf cc-src-cap + 1- c@ [lit] 65 = assert cc-pp-out-pos @ cc-src-cap = assert cc-out-buf c@ [lit] 90 = assert'))
 forth(tag+'-source-one-past',out(sink+'[lit] 66 cc-prep-emit-byte'),36)
 # Output text can fill its independent selected capacity exactly.
 output=setup+'cc-out-cap 1- cc-out-pos ! [lit] 165 cc-emit-byte\n'
 forth(tag+'-output-exact',out(output+'cc-out-pos @ cc-out-cap = assert cc-out-buf cc-out-cap + 1- c@ [lit] 165 = assert'))
 forth(tag+'-output-one-past',out(output+'[lit] 90 cc-emit-byte'),21)
 # File-backed text/rodata/data slices must not overlap the relocation table.
 obj=setup+'cc-obj-init\n'
 forth(tag+'-object-slice-layout',out(obj+'cc-obj-rodata cc-obj-base cc-obj-text cc-obj-base - cc-obj-text-cap = assert cc-obj-data cc-obj-base cc-obj-rodata cc-obj-base - cc-obj-section-cap = assert'))
 for section,capacity in [('cc-obj-text','cc-obj-text-cap'),('cc-obj-rodata','cc-obj-section-cap'),('cc-obj-data','cc-obj-section-cap')]:
  exact=obj+section+' cc-obj-use '+capacity+' cc-obj-reserve drop\n'
  forth(tag+'-'+section+'-exact',out(exact+section+' cc-obj-length '+capacity+' = assert'))
  forth(tag+'-'+section+'-one-past',out(exact+'[lit] 1 cc-obj-reserve drop'),245)
 # Relocations fill all five cells in the final row, after width/id checks.
 rel=obj+'create name s, target name [lit] 6 cc-obj-global cc-obj-func cc-obj-default cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol drop [lit] 8 cc-obj-reserve drop cc-obj-reloc-cap 1- cc-obj-nrel ! cc-obj-text [lit] 0 cc-obj-r64 [lit] 1 [lit] 17 cc-obj-reloc\n'
 forth(tag+'-relocation-exact',out(rel+'cc-obj-reloc-cap 1- cc-obj-rel dup @ cc-obj-text = assert dup [lit] 8 + @ 0= assert dup [lit] 16 + @ cc-obj-r64 = assert dup [lit] 24 + @ [lit] 1 = assert [lit] 32 + @ [lit] 17 = assert'))
 forth(tag+'-relocation-one-past',out(rel+'cc-obj-text [lit] 0 cc-obj-r64 [lit] 1 [lit] 17 cc-obj-reloc'),245)
 labels=setup+'create label-name s, label cc-label-cap 1- cc-label-count ! label-name [lit] 5 cc-label-create\n'
 forth(tag+'-label-exact-five-arrays',out(labels+'dup cc-label-cap 1- = assert dup cc-label-name-addr cell[] @ label-name = assert dup cc-label-name-len cell[] @ [lit] 5 = assert dup cc-label-vaddr-of 0= assert dup cc-label-fixups @ 0= assert cc-label-switch-depth cell[] @ 0= assert'))
 forth(tag+'-label-one-past',out(labels+'drop label-name [lit] 5 cc-label-create drop'),171)
 fix=setup+'cc-gfixup-cap 1- cc-gfixup-count ! [lit] 123 [lit] 456 cc-gfixup-add\n'
 forth(tag+'-global-fixup-exact',out(fix+'cc-gfixup-cap 1- cc-gfixup-out-pos cell[] @ [lit] 123 = assert cc-gfixup-cap 1- cc-gfixup-slot cell[] @ [lit] 456 = assert'))
 forth(tag+'-global-fixup-one-past',out(fix+'[lit] 789 [lit] 123 cc-gfixup-add'),81)
 forth(tag+'-global-fixup-reset',out(fix+'cc-globals-init cc-gfixup-count @ 0= assert [lit] 789 [lit] 123 cc-gfixup-add [lit] 0 cc-gfixup-out-pos cell[] @ [lit] 789 = assert [lit] 0 cc-gfixup-slot cell[] @ [lit] 123 = assert'))
 # All six macro arrays' last records are exercised and address checked.
 capexpr='cc-macro-cap' if direct else '[lit] 1024'
 macro=setup+('true cc-prep-direct !\n' if direct else '[lit] 0 cc-prep-direct !\n')+capexpr+' 1- cc-macro-count ! [lit] 123 [lit] 7 [lit] 456 [lit] 9 true cc-macro-record\n'
 checks=capexpr+' 1- >r r@ cc-macro-name-addr cell[] @ [lit] 123 = assert r@ cc-macro-name-len cell[] @ [lit] 7 = assert r@ cc-macro-body-addr cell[] @ [lit] 456 = assert r@ cc-macro-body-len cell[] @ [lit] 9 = assert r@ cc-macro-params cell[] @ true = assert r> cc-macro-busy cell[] @ 0= assert'
 forth(tag+'-macro-exact-six-arrays',out(macro+checks))
 forth(tag+'-macro-one-past',out(macro+'[lit] 0 [lit] 0 [lit] 0 [lit] 0 true cc-macro-record'),34)
 for bad in ('[lit] 0','true','[lit] 9223372036854775808','cc-om-cap 1+'):
  forth(tag+'-invalid-record-'+bad,out(setup+bad+' cc-om-record drop'),245)
 om=setup+'cc-om-cap 1- cc-om-count ! [lit] 123 [lit] 7 cc-obj-global cc-obj-func cc-om-new\n'
 forth(tag+'-stable-record-exact',out(om+'dup cc-om-cap = assert dup om-name @ [lit] 123 = assert om-align @ [lit] 1 = assert'))
 forth(tag+'-stable-record-one-past',out(om+'drop [lit] 0 [lit] 0 cc-obj-global cc-obj-func cc-om-new drop'),245)
# Native/direct preprocessing without workspace selection keeps its 4096 cap.
macro='true cc-prep-direct ! cc-macro-cap [lit] 4096 = assert cc-macro-cap 1- cc-macro-count ! [lit] 123 [lit] 7 [lit] 456 [lit] 9 true cc-macro-record\n'
forth('native-default-storage-macro-exact',out(macro+'cc-macro-count @ [lit] 4096 = assert'))
forth('native-default-storage-macro-one-past',out(macro+'[lit] 0 [lit] 0 [lit] 0 [lit] 0 true cc-macro-record'),34)
# Preprocessing twice resets names, pool, source and all busy slots as recorded.
forth('repeated-preprocess-reset',out('''
cc-io-direct-workspace cc-prep-direct-workspace
true cc-prep-direct ! [lit] 0 cc-in-len ! cc-preprocess
cc-macro-count @ [lit] 0 = assert cc-src-len @ 0= assert
[lit] 17 cc-macro-count ! [lit] 19 cc-macro-pool-pos ! [lit] 23 cc-src-len !
cc-preprocess cc-macro-count @ 0= assert cc-macro-pool-pos @ 0= assert cc-src-len @ 0= assert
'''))
(WORK/'report.json').write_text(json.dumps({'seed_sha256':hashlib.sha256((ROOT/'seed-forth').read_bytes()).hexdigest(),'cases':records},indent=2)+'\n')
print(f'PASS {len(records)} workspace cases: {WORK}/report.json')
