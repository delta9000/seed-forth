#!/usr/bin/env python3
"""Fixed C-locale wide primitives and LP64 wcstol, independent expected values."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2];(ROOT/'build-out').mkdir(exist_ok=True);OUT=Path(tempfile.mkdtemp(prefix='wide-check-',dir=ROOT/'build-out'));CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(args):
 r=subprocess.run(list(map(str,args)),capture_output=True,timeout=120);assert r.returncode==0,(args,r.returncode,r.stdout[-200:],r.stderr);return r
expected=[]
for i in range(256):
 expected.append(f'm {i} {0 if i==0 else 1 if i<128 else -1} {i if i<128 else 999} {33 if i<128 else 84}')
 expected.append(f'w {i} {1 if i<128 else -1} {i if i<128 else 33} {33 if i<128 else 84}')
 expected.append(f'c {i} {int(32<=i<=126)} {int(i in [9,10,11,12,13,32])}')
expected='\n'.join(expected)+'\nboundaries passed\n'
identity=run(CC+['--print-source-hash']).stdout.decode().strip();character=OUT/'characters';run(CC+['-o',character,ROOT/'tests/gcc/wide-character-check.c']);r=run([character]);assert r.stdout.decode()==expected and not r.stderr
MAX=(1<<63)-1;MIN=-(1<<63);cases=[]
def encode(value,base):
 s='';digits='0123456789abcdefghijklmnopqrstuvwxyz'
 while value:s=digits[value%base]+s;value//=base
 return s or '0'
def add(text,base,value,end,error=33):cases.append((text,base,value,end,error))
for base in range(2,37):
 for number in [0,1,base-1,base,MAX]:
  text=encode(number,base);add(text+'!',base,number,len(text))
  if number==MAX and base>10:add(text.upper()+'!',base,number,len(text))
 text=encode(MAX,base);add('-'+text+'!',base,-MAX,len(text)+1)
 text=encode(MAX+1,base);add('-'+text+'!',base,MIN,len(text)+1);add(text+'!',base,MAX,len(text),34)
 text=encode(MAX+2,base);add('-'+text+'!',base,MIN,len(text)+1,34)
for item in [('',10,0,0,33),('  +!',0,0,0,33),('-0!',0,0,2,33),('0777!',0,511,4,33),('08!',0,0,1,33),('0x',0,0,1,33),('0X!',16,0,1,33),('-0x10!',0,-16,5,33),('+0XFF!',16,255,5,33),('0b10!',0,0,1,33),('123',1,0,0,22),('123',37,0,0,22),('123',-1,0,0,22),('999999999999999999999999999999!',10,MAX,30,34),(' \t\r\n\v\f+123!',0,123,10,33)]:add(*item)
def quote(s):return '"'+''.join('\\%03o'%ord(c) for c in s)+'"'
source=OUT/'number.c';source.write_text('#include <stdlib.h>\n#include <stdio.h>\n#include <errno.h>\n#include <wchar.h>\nstruct test { const char *text; int base; };\nstatic struct test cases[]={\n'+''.join('{'+quote(t)+','+str(b)+'},\n' for t,b,_,_,_ in cases)+'''};
int main(void) {
 wchar_t text[128]; wchar_t *end; unsigned int i; unsigned int j; long value;
 wchar_t unusual[3]={0x2003,'1',0};
 end=unusual; errno=EDOM;
 if(wcstol(unusual,&end,10)!=0 || end!=unusual || errno!=EDOM) return 1;
 unusual[0]='4'; unusual[1]='2';
 if(wcstol(unusual,0,10)!=42) return 2;
 for(i=0;i<sizeof(cases)/sizeof(cases[0]);i++) {
  for(j=0;cases[i].text[j];j++) text[j]=(unsigned char)cases[i].text[j];
  text[j]=0; end=text; errno=EDOM;
  value=wcstol(text,&end,cases[i].base);
  printf("%ld %ld %d\\n",value,(long)(end-text),errno);
 }
 return 0;
}
''');number=OUT/'numbers';run(CC+['-o',number,source]);result=run([number]);expected_numbers=''.join(f'{v} {end} {error}\n' for _,_,v,end,error in cases)
if result.stdout.decode()!=expected_numbers:
 for i,(a,b) in enumerate(zip(result.stdout.decode().splitlines(),expected_numbers.splitlines())):
  if a!=b:raise AssertionError((i,cases[i],a,b))
 raise AssertionError('number output length mismatch')
report={'compiler_source_identity':identity,'byte_values':256,'wcstol_cases':len(cases),'reset_null_zero_WEOF_and_high_codepoint_boundaries':True,'host_oracles':[]};host=shutil.which('gcc')
if host:
 for level in ['-O0','-O2']:
  for label,file,output in [('characters',ROOT/'tests/gcc/wide-character-check.c',expected),('numbers',source,expected_numbers)]:
   target=OUT/('host-'+label+level[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-DWIDE_HOST_ORACLE',level,file,'-o',target]);r=run([target]);assert r.stdout.decode()==output and not r.stderr,(level,label,r.stdout,r.stderr)
  report['host_oracles'].append(level)
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip(),'compiler changed during check'
names=['runtime/gcc-seed/wide.c','runtime/gcc-seed/include/inttypes.h','runtime/gcc-seed/include/wchar.h','runtime/gcc-seed/include/wctype.h','runtime/gcc-seed/include/stddef.h','runtime/gcc-seed/include/stdlib.h','runtime/gcc-seed/include/limits.h','runtime/gcc-seed/include/errno.h','tests/gcc/wide-character-check.c','tests/gcc/wide-check.py'];report['source_sha256']={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names};report['artifact_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.is_file()};(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: ASCII wide primitives,',len(cases),'wcstol cases; hostO0/O2:',bool(host));print(OUT/'report.json')
