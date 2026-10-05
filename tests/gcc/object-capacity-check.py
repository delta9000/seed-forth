#!/usr/bin/env python3
"""Direct-only record/ELF symbol/string bounds; host tools are independent oracles."""
from pathlib import Path
import hashlib,json,os,resource,signal,struct,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
WORK=Path(tempfile.mkdtemp(prefix='object-capacity-',dir=ROOT/'build-out'))
NAMES=['010-lib.fth']+[p.name for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')) if p.name!='120-cc-main.fth']+['141-archive.fth']
BASE=b'\n'.join((ROOT/n).read_bytes() for n in NAMES)
PREFIX=b'\n[lit] 77 cc-src-line ! : assert 0= if, [lit] 99 die then, ;\n'
records=[]
def run(cmd,**kw):
 p=subprocess.Popen(cmd,start_new_session=True,**kw)
 try:out,err=p.communicate(timeout=120)
 except subprocess.TimeoutExpired:
  os.killpg(p.pid,signal.SIGKILL);p.communicate();raise
 return subprocess.CompletedProcess(cmd,p.returncode,out,err)
def forth(name,body,status=0,base=BASE):
 # Keep input in communicate, and kill the complete bounded process group on timeout.
 p=subprocess.Popen([ROOT/'seed-forth'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
 try:out,err=p.communicate(base+PREFIX+body.encode()+b'\nbye\n',timeout=90)
 except subprocess.TimeoutExpired:
  os.killpg(p.pid,signal.SIGKILL);p.communicate();raise
 expected=f'cc: line 77: error {status}\n'.encode() if status else b''
 assert (p.returncode,out,err)==(status,b'',expected),(name,p.returncode,out,err)
 records.append({'case':name,'status':status})
def pathword(name,path):return f'create {name} s, {path} [lit] 0 c,\n'
# Selection, caching, exact mmap request, all layout edges and restored defaults.
forth('layout-cache-default-reset','''
cc-obj-symbol-cap [lit] 2048 = assert cc-om-cap [lit] 4096 = assert
variable calls : map-count [lit] 1 calls +!
  calls @ [lit] 1 = if, dup [lit] 9834496 = assert
  else, dup [lit] 1376256 = assert then, cc-workspace-syscall ;
' map-count is cc-workspace-syscall-fwd
[lit] 71 cc-obj-default-symbols ! [lit] 72 cc-om-default-records ! [lit] 73 cc-obj-default-strings c!
cc-obj-direct-workspace cc-om-direct-workspace
calls @ [lit] 2 = assert cc-obj-symbol-cap [lit] 8192 = assert cc-om-cap [lit] 10752 = assert
cc-obj-symbols cc-obj-relocs - cc-obj-reloc-cap [lit] 40 * = assert
cc-obj-strings cc-obj-symbols - cc-obj-direct-symbol-bytes = assert
cc-obj-string-cap [lit] 77824 = assert
[lit] 74 cc-obj-strings c! [lit] 75 cc-obj-strings cc-obj-string-cap + 1- c!
cc-obj-symbol-cap cc-obj-sym [lit] 56 + [lit] 0 swap !
cc-obj-strings c@ [lit] 74 = assert cc-obj-strings cc-obj-string-cap + 1- c@ [lit] 75 = assert
cc-obj-relocs cc-obj-payload - cc-obj-direct-payload-bytes = assert
cc-obj-direct-symbol-bytes cc-obj-symbol-cap 1+ [lit] 64 * = assert
[lit] 0 cc-obj-sym cc-obj-symbols = assert
cc-obj-symbol-cap cc-obj-sym [lit] 64 + cc-obj-symbols - cc-obj-direct-symbol-bytes = assert
cc-om-cap cc-om-record [lit] 128 + cc-om-records - cc-om-cap [lit] 128 * = assert
cc-obj-symbols cc-om-records cc-obj-direct-workspace cc-om-direct-workspace
cc-om-records = assert cc-obj-symbols = assert calls @ [lit] 2 = assert
[lit] 17 cc-obj-nsym ! [lit] 19 cc-om-count ! [lit] 23 cc-obj-nstr !
cc-obj-default-workspace cc-om-default-workspace
cc-obj-nsym @ [lit] 17 = assert cc-om-count @ [lit] 19 = assert cc-obj-nstr @ [lit] 23 = assert
cc-obj-strings cc-obj-default-strings = assert cc-obj-strings c@ [lit] 73 = assert
cc-obj-string-cap [lit] 65536 = assert
cc-obj-symbols cc-obj-default-symbols = assert cc-obj-symbols @ [lit] 71 = assert
cc-om-records cc-om-default-records = assert cc-om-records @ [lit] 72 = assert
cc-obj-symbol-cap [lit] 2048 = assert cc-om-cap [lit] 4096 = assert
cc-obj-direct-workspace cc-om-direct-workspace calls @ [lit] 2 = assert
cc-obj-nstr @ [lit] 23 = assert cc-obj-strings c@ [lit] 74 = assert
cc-obj-strings cc-obj-string-cap + 1- c@ [lit] 75 = assert
cc-obj-init cc-obj-nsym @ 0= assert cc-obj-nstr @ [lit] 1 = assert
cc-obj-nrel @ 0= assert cc-obj-string-cap [lit] 77824 = assert
cc-obj-reloc-cap [lit] 20992 = assert
[lit] 123 cc-om-count ! [lit] 456 cc-om-relocations ! cc-sysv-object-enable
cc-om-count @ 0= assert cc-om-relocations @ 0= assert cc-om-cap [lit] 10752 = assert
''')
# Real mmap failure must not publish new pointers, caps, counts, or output.
needle=b': cc-die\n';assert BASE.count(needle)==1
hookbase=BASE.replace(needle,b"defer inspect-error\n: noop ; ' noop is inspect-error\n: cc-die\n inspect-error\n")
for word,prefix,oldcap in [('cc-obj-direct-workspace','cc-obj',2048),('cc-om-direct-workspace','cc-om',4096)]:
 for err in [0,-1,-12,-4095]:
  checks=('cc-obj-symbols cc-obj-default-symbols = assert cc-obj-symbol-cap [lit] 2048 = assert cc-obj-direct-base @ 0= assert cc-obj-strings cc-obj-default-strings = assert cc-obj-string-cap [lit] 65536 = assert' if prefix=='cc-obj' else 'cc-om-records cc-om-default-records = assert cc-om-cap [lit] 4096 = assert cc-om-direct-base @ 0= assert')
  forth(word+'-map-'+str(err),f": inspect {checks} ; ' inspect is inspect-error\n: fail-map drop [lit] {err%2**64} ; ' fail-map is cc-workspace-syscall-fwd\n{word}",245,hookbase)
for direct in (False,True):
 setup='cc-obj-direct-workspace cc-om-direct-workspace\n' if direct else ''
 tag='direct' if direct else 'default'
 forth(tag+'-null-symbol-public-id',setup+'cc-obj-init [lit] 0 cc-obj-check-id',246)
 for bad in ['true','[lit] 9223372036854775808','[lit] 9223372036854775807','cc-obj-symbol-cap 1+']:
  forth(tag+'-invalid-symbol-'+bad,setup+bad+' cc-obj-sym drop',246)
 for bad in ['[lit] 0','true','[lit] 9223372036854775808','[lit] 9223372036854775807','cc-om-cap 1+']:
  forth(tag+'-invalid-record-'+bad,setup+bad+' cc-om-record drop',245)
 # Every cell in the final symbol row, including late-assigned ELF index.
 fill=setup+'''cc-obj-init create name s, abc
cc-obj-symbol-cap 1- cc-obj-nsym !
name [lit] 3 cc-obj-weak cc-obj-object cc-obj-hidden cc-obj-abs [lit] 123 [lit] 456 cc-obj-symbol
'''
 forth(tag+'-symbol-last-eight-cells',fill+'''dup cc-obj-symbol-cap = assert cc-obj-sym
[lit] 789 over [lit] 56 + !
dup @ [lit] 1 = assert dup [lit] 8 + @ [lit] 2 = assert
dup [lit] 16 + @ [lit] 1 = assert dup [lit] 24 + @ [lit] 2 = assert
dup [lit] 32 + @ cc-obj-abs = assert dup [lit] 40 + @ [lit] 123 = assert
dup [lit] 48 + @ [lit] 456 = assert [lit] 56 + @ [lit] 789 = assert
''')
 forth(tag+'-symbol-one-past',fill+'drop name [lit] 3 cc-obj-local cc-obj-notype cc-obj-default cc-obj-abs [lit] 0 [lit] 0 cc-obj-symbol drop',245)
 # All sixteen cells are inside the last stable record; creation zeroes reuse.
 om=setup+'''cc-om-cap cc-om-record [lit] 128 [lit] 165 cc-nfill
cc-om-cap 1- cc-om-count ! [lit] 123 [lit] 7 cc-obj-global cc-obj-func cc-om-new
'''
 # cc-nfill is not part of the compiler API; write cells with a local loop.
 om=om.replace('cc-om-cap cc-om-record [lit] 128 [lit] 165 cc-nfill',': dirty [lit] 0 begin, dup [lit] 16 < while, true over [lit] 8 * cc-om-cap cc-om-record + ! 1+ repeat, drop ; dirty')
 checks='dup cc-om-cap = assert dup om-name @ [lit] 123 = assert dup om-nlen @ [lit] 7 = assert dup om-bind @ [lit] 1 = assert dup om-kind @ [lit] 2 = assert dup om-align @ [lit] 1 = assert\n'
 for offset in [32,40,48,64,72,80,88,96,104,112,120]:checks+=f'dup cc-om-record [lit] {offset} + @ 0= assert\n'
 forth(tag+'-record-last-sixteen-cells',om+checks+'drop')
 forth(tag+'-record-one-past',om+'drop [lit] 0 [lit] 0 [lit] 0 [lit] 0 cc-om-new drop',245)
 # Both selected string bounds include leading and trailing NULs.
 strings=setup+'''cc-obj-init cc-obj-string-cap [lit] 2 - constant long-name-size
create long-name long-name-size allot
: fill-name [lit] 0 begin, dup long-name-size < while, [lit] 120 over long-name + c! 1+ repeat, drop ; fill-name
long-name long-name-size cc-obj-local cc-obj-notype cc-obj-default cc-obj-abs [lit] 0 [lit] 0 cc-obj-symbol drop
'''
 forth(tag+'-string-exact',strings+'cc-obj-nstr @ cc-obj-string-cap = assert cc-obj-strings c@ 0= assert cc-obj-strings cc-obj-string-cap + 1- c@ 0= assert')
 forth(tag+'-string-one-past',strings+'long-name [lit] 1 cc-obj-local cc-obj-notype cc-obj-default cc-obj-abs [lit] 0 [lit] 0 cc-obj-symbol drop',245)
 forth(tag+'-string-nul-reserve',strings+'[lit] 0 [lit] 0 cc-obj-local cc-obj-notype cc-obj-default cc-obj-abs [lit] 0 [lit] 0 cc-obj-symbol drop',245)
 for exists in (False,True):
  output=WORK/(tag+'-string-publication-'+str(exists)+'.o')
  if exists:output.write_bytes(b'old object')
  forth(tag+'-string-publication-'+str(exists),strings+pathword('output',output)+'long-name [lit] 1 cc-obj-local cc-obj-notype cc-obj-default cc-obj-abs [lit] 0 [lit] 0 cc-obj-symbol drop output cc-obj-write',245)
  assert output.exists()==exists
  if exists:assert output.read_bytes()==b'old object'
  assert not list(WORK.glob(output.name+'.obj-*'))
# Fill the REAL public API. Globals inserted first/last, locals must serialize first.
large='''
cc-obj-direct-workspace cc-obj-init
[lit] 191 cc-obj-byte [lit] 0 cc-obj-4le
[lit] 184 cc-obj-byte [lit] 60 cc-obj-4le [lit] 15 cc-obj-byte [lit] 5 cc-obj-byte
create entry s, _start
entry [lit] 6 cc-obj-global cc-obj-func cc-obj-default cc-obj-text [lit] 0 [lit] 12 cc-obj-symbol [lit] 1 = assert
: fill-locals begin, cc-obj-nsym @ cc-obj-symbol-cap 1- < while,
[lit] 0 [lit] 0 cc-obj-local cc-obj-section cc-obj-default cc-obj-text [lit] 0 [lit] 0 cc-obj-symbol drop repeat, ; fill-locals
create answer s, answer
answer [lit] 6 cc-obj-global cc-obj-notype cc-obj-default cc-obj-abs [lit] 42 [lit] 0 cc-obj-symbol cc-obj-symbol-cap = assert
cc-obj-text [lit] 1 cc-obj-r32 cc-obj-symbol-cap [lit] 0 cc-obj-reloc
[lit] 123 [lit] 0 cc-obj-sym !
'''
obj=WORK/'large.o';forth('full-direct-object',large+pathword('output',obj)+'output cc-obj-write')
data=obj.read_bytes();shoff=struct.unpack_from('<Q',data,40)[0];rows=[struct.unpack_from('<IIQQQQIIQQ',data,shoff+i*64) for i in range(10)]
sym=rows[7];strs=rows[8];symbols=[struct.unpack_from('<IBBHQQ',data,sym[4]+i*24) for i in range(sym[5]//24)]
assert len(symbols)==8193 and symbols[0]==(0,)*6
assert sym[7]==8191 and all(s[1]>>4==0 for s in symbols[:8191])
assert all(s[1]>>4==1 for s in symbols[8191:])
assert symbols[-1][-2:]==(42,0)
off,info,addend=struct.unpack_from('<QQq',data,rows[5][4]);assert (off,info>>32,info&0xffffffff,addend)==(1,8192,10,0)
for cmd in [['readelf','-aW',str(obj)],['ld','-e','_start','-o',str(WORK/'host-linked'),str(obj)]]:
 p=run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE);assert p.returncode==0 and not p.stderr,(cmd,p)
 if cmd[0]=='readelf':(WORK/'large.readelf.txt').write_bytes(p.stdout)
forth('forth-reader-link-large',pathword('input',obj)+pathword('output',WORK/'forth-linked')+'''lnk-init input lnk-add-object create entry s, _start entry [lit] 6 lnk-entry output lnk-link''')
for name in ['host-linked','forth-linked']:
 p=run([WORK/name],stdout=subprocess.PIPE,stderr=subprocess.PIPE);assert (p.returncode,p.stdout,p.stderr)==(42,b'',b'')
 records.append({'case':name,'exit':42})
for exists in (False,True):
 output=WORK/('preserve-'+str(exists)+'.o')
 if exists:output.write_bytes(b'old object')
 bad=large+pathword('output',output)+'answer [lit] 6 cc-obj-global cc-obj-notype cc-obj-default cc-obj-abs [lit] 42 [lit] 0 cc-obj-symbol drop output cc-obj-write'
 forth('publication-'+str(exists),bad,245)
 assert output.exists()==exists
 if exists:assert output.read_bytes()==b'old object'
 assert not list(WORK.glob(output.name+'.obj-*'))
# Reset produces the original empty writer bytes under both selections.
for name,body in [('empty','cc-obj-init'),('reset',large+'cc-obj-init')]:
 p=WORK/(name+'.o');forth(name,pathword('out',p)+body+' out cc-obj-write')
assert (WORK/'empty.o').read_bytes()==(WORK/'reset.o').read_bytes()
report={'status':'PASS','seed_sha256':hashlib.sha256((ROOT/'seed-forth').read_bytes()).hexdigest(),'large_object_sha256':hashlib.sha256(data).hexdigest(),'cases':records}
(WORK/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'PASS {len(records)} object-capacity cases: {WORK}/report.json')
