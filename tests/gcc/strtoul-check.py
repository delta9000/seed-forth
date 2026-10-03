#!/usr/bin/env python3
"""Forth-only numeric/end-pointer tests with a separate optional libc oracle."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='strtoul-check-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
MAX=(1<<64)-1
cases=[]
def add(text,base,value,end,error=33):cases.append((text,base,value,end,error))
def encoded(value,base):
 digits='0123456789abcdefghijklmnopqrstuvwxyz';result=''
 while value:
  result=digits[value%base]+result;value//=base
 return result or '0'
for base in range(2,37):
 for value in [0,1,base-1,base,base*base+1,MAX]:
  text=encoded(value,base)
  add(text+'!',base,value,len(text))
  if value==MAX and base>10:add(text.upper()+'!',base,value,len(text))
  if value in [1,MAX]:add(' \t-'+text+'!',base,(-value)&MAX,len(text)+3)
 text=encoded(MAX+1,base)
 add(text+'zzz!',base,MAX,len(text)+(3 if base==36 else 0),34)
 # A magnitude overflow remains ERANGE even with a minus sign.
 add('-'+text+'!',base,MAX,len(text)+1,34)
for text,base,value,end,error in [
 ('-0!',0,0,2,33),('',10,0,0,33),(' \t\n',0,0,0,33),('+',0,0,0,33),('-',0,0,0,33),
 ('  +!',10,0,0,33),('xyz',10,0,0,33),('0',0,0,1,33),('08',0,0,1,33),
 ('09',0,0,1,33),('0777!',0,511,4,33),('0x',0,0,1,33),('0X!',16,0,1,33),
 ('0xg',16,0,1,33),('0x0!',0,0,3,33),('0xABCdef!',0,11259375,8,33),
 ('+0Xf!',16,15,4,33),('-0x10!',0,MAX-15,5,33),('0x10!',10,0,1,33),
 ('0b10!',0,0,1,33),('0b10!',2,0,1,33),('  \t\r\n\v\f+123!',0,123,11,33),
 ('18446744073709551615!',10,MAX,20,33),('18446744073709551616!',10,MAX,20,34),
 ('184467440737095516159999999999999!',10,MAX,33,34),
 ('\x80'+'12',10,0,0,33),('12\x80',10,12,2,33),('123',1,0,0,22),
 ('123',37,0,0,22),('123',-1,0,0,22),('00000000000000000000000000000001!',10,1,32,33),
 ]:add(text,base,value,end,error)
def quote(text):return '"'+''.join('\\%03o'%ord(c) for c in text)+'"'
source=OUT/'fixture.c'
source.write_text('#include <stdlib.h>\n#include <stdio.h>\n#include <errno.h>\nstruct test { const char *text; int base; };\nstatic struct test cases[] = {\n'+''.join('{'+quote(t)+','+str(b)+'},\n' for t,b,_,_,_ in cases)+'};\nint main(void) {\n unsigned long value; char *end; unsigned int i;\n errno = EDOM;\n if (strtoul("42!", 0, 10) != 42UL || errno != EDOM) return 2;\n for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {\n  end = (char *)cases[i].text; errno = EDOM;\n  value = strtoul(cases[i].text, &end, cases[i].base);\n  printf("%lu %ld %d\\n", value, (long)(end - cases[i].text), errno);\n }\n return ferror(stdout) ? 1 : 0;\n}\n')
def run(args):
 r=subprocess.run([str(x) for x in args],capture_output=True,timeout=120)
 if r.returncode:raise AssertionError((args,r.returncode,r.stderr.decode(errors='replace')))
 return r
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
executable=OUT/'forth-strtoul'
run(CC+['-o',executable,source]);actual=run([executable]).stdout.decode()
expected=''.join(f'{v} {end} {error}\n' for _,_,v,end,error in cases)
if actual!=expected:
 for i,(a,b) in enumerate(zip(actual.splitlines(),expected.splitlines())):
  if a!=b:raise AssertionError((i,cases[i],a,b))
 raise AssertionError('output length differs')
report={'compiler_source_identity':identity,'production_cases':len(cases),'production_passed':True,'host_oracles':[],'runtime_sha256':hashlib.sha256((ROOT/'runtime/gcc-seed/strtoul.c').read_bytes()).hexdigest(),'fixture_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'production_executable_sha256':hashlib.sha256(executable.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(actual.encode()).hexdigest()}
host=shutil.which('gcc')
if host:
 for optimization in ['-O0','-O2']:
  oracle=OUT/('host-strtoul'+optimization[1:])
  run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror',optimization,source,'-o',oracle])
  output=run([oracle]).stdout.decode()
  assert output==actual,optimization+' host comparison differs'
  report['host_oracles'].append({'optimization':optimization,'matches_forth':True})
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip(),'compiler changed during check'
(OUT/'actual.txt').write_text(actual);(OUT/'expected.txt').write_text(expected)
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS:',len(cases),'Forth strtoul cases; host C90 O0/O2:',bool(host))
print('Report:',OUT/'report.json')
