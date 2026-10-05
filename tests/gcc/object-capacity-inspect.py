#!/usr/bin/env python3
"""Independent ABI decoding of the complete retained c-common ELF object."""
from pathlib import Path
import argparse,hashlib,json,os,resource,signal,struct,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('object',type=Path);a=p.parse_args()
ROOT=Path(__file__).resolve().parents[2];resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
obj=a.object.resolve();data=obj.read_bytes();assert len(data)==1653208
assert hashlib.sha256(data).hexdigest()=='d965b3ae73a01ffeff2b745ad0cd28d434542cf130e9619948c2458eb2df931b'
h=struct.unpack_from('<16sHHIQQQIHHHHHH',data);assert h[:4]==(b'\x7fELF\x02\x01\x01'+b'\0'*9,1,62,1)
assert h[-3:]==(64,10,9);rows=[struct.unpack_from('<IIQQQQIIQQ',data,h[6]+64*i) for i in range(10)]
assert rows[0]==(0,)*10
names=data[rows[9][4]:rows[9][4]+rows[9][5]];sections={}
for i,r in enumerate(rows[1:],1):
 assert r[0]<len(names) and b'\0' in names[r[0]:];name=names[r[0]:].split(b'\0',1)[0].decode();sections[name]=(i,r)
 assert r[8]>0 and r[8]&(r[8]-1)==0 and r[4]%r[8]==0
 assert r[1]==8 or r[4]+r[5]<=h[6]
assert list(sections)==['.text','.rodata','.data','.bss','.rela.text','.rela.data','.symtab','.strtab','.shstrtab']
sym=rows[7];strings=data[rows[8][4]:rows[8][4]+rows[8][5]];assert len(strings)==60259 and strings[0]==0
assert sym[5]==6283*24 and sym[6]==8 and sym[9]==24 and sym[7]==5981
symbols=[]
for i in range(sym[5]//24):
 s=struct.unpack_from('<IBBHQQ',data,sym[4]+i*24);symbols.append(s)
 assert s[0]<len(strings) and b'\0' in strings[s[0]:]
 assert ((s[1]>>4)==0)==(i<sym[7])
 assert s[3] in (0,1,2,3,4,65521)
 if s[3] in (1,2,3,4):assert s[4]+s[5]<=rows[s[3]][5]
assert symbols[0]==(0,)*6
relocations=0
for i,target in ((5,1),(6,3)):
 r=rows[i];assert r[6:8]==(7,target) and r[9]==24 and r[5]%24==0
 for j in range(r[5]//24):
  off,info,addend=struct.unpack_from('<QQq',data,r[4]+j*24);kind=info&0xffffffff;symbol=info>>32
  assert kind in (1,2,4,10,11) and 0<symbol<len(symbols)
  assert off+(8 if kind==1 else 4)<=rows[target][5]
  relocations+=1
assert relocations==13556
work=Path(tempfile.mkdtemp(prefix='c-common-object-inspect-',dir=ROOT/'build-out'))
def run(cmd,stdin=None):
 p=subprocess.Popen(cmd,stdin=subprocess.PIPE if stdin is not None else None,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
 try:out,err=p.communicate(stdin,timeout=120)
 except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.communicate();raise
 assert (p.returncode,err)==(0,b''),(cmd,p.returncode,err)
 return out
(work/'readelf.txt').write_bytes(run(['readelf','-aW',obj]))
base=b'\n'.join((ROOT/n).read_bytes() for n in ['010-lib.fth','020-cc-arena.fth','030-cc-io.fth','140-cc-link.fth'])
body=f'\ncreate input s, {obj} [lit] 0 c,\nlnk-init input lnk-add-object bye\n'.encode();assert run([ROOT/'seed-forth'],base+body)==b''
report={'status':'PASS','object':str(obj),'sha256':hashlib.sha256(data).hexdigest(),'object_bytes':len(data),'symbols_excluding_null':len(symbols)-1,'symbol_strings_bytes':len(strings),'relocations':relocations,'section_bytes':{name:r[5] for name,(i,r) in sections.items()},'readelf':'PASS','forth_reader':'PASS','scope':'complete unit structural/read-only validation, not cc1 linking or execution'}
(work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));print(work/'report.json')
