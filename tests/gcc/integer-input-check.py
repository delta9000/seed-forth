#!/usr/bin/env python3
"""Measured integer scanf/atoi, independent values and host C90 oracles."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2];(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='integer-input-',dir=ROOT/'build-out'));CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(args):
    r=subprocess.run(list(map(str,args)),capture_output=True,timeout=120)
    assert r.returncode==0,(args,r.returncode,r.stdout[-300:],r.stderr)
    return r
def quote(text):return '"'+''.join('\\%03o'%ord(c) for c in text)+'"'
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
source=ROOT/'tests/gcc/integer-input-check.c';production=OUT/'boundaries';run(CC+['-o',production,source]);r=run([production]);assert r.stdout==b'integer input boundaries passed\n' and not r.stderr
cases=[]
signed=[0,1,7,8,15,16,127,255,256,32767,65535,2147483647,-1,-7,-8,-15,-127,-255,-256,-32768,-2147483647,-2147483648]
for value in signed:
    for prefix,suffix in [('', ''),(' \t\n','!'),('+','z')]:
        if prefix=='+' and value<0:continue
        cases.append((prefix+str(value)+suffix,'%d',1,value,0))
unsigned=[0,1,7,8,15,16,127,255,256,32767,65535,2147483647,2147483648,4294967295]
for fmt,base in [('%o',8),('%x',16)]:
    for value in unsigned:
        digits=format(value,'o' if base==8 else 'x')
        for prefix in ['', '+', '-', ' \r\n']:
            cases.append((prefix+digits+'!',fmt,1,0,(-value if prefix=='-' else value)&0xffffffff))
        if base==16:
            cases.append(('0x'+digits,fmt,1,0,value));cases.append(('-0X'+digits.upper(),fmt,1,0,(-value)&0xffffffff))
for text,fmt,result in [('', '%d',-1),(' \t','%o',-1),('+','%d',0),('-','%x',0),('word','%d',0),('8','%o',0),('g','%x',0)]:cases.append((text,fmt,result,123,123))
host=shutil.which('gcc');report={'compiler_source_identity':identity,'scanf_numeric_cases':len(cases),'atoi_cases':len(signed)*2+5,'host_oracles':[]}
sources=[]
for start in range(0,len(cases),150):
    part=cases[start:start+150];path=OUT/f'numeric-{start}.c'
    code='#include <stdio.h>\n#include <stdlib.h>\n#include <errno.h>\nstruct item {const char *text; const char *format;};\nstatic struct item cases[]={\n'+''.join('{'+quote(t)+','+quote(f)+'},\n' for t,f,_,_,_ in part)+'''};
int main(void) { unsigned int i; unsigned int u; int d; int count;
 for(i=0;i<sizeof(cases)/sizeof(cases[0]);i++) {
  d=123;u=123;errno=EDOM;
  if(cases[i].format[1]=='d') count=sscanf(cases[i].text,cases[i].format,&d);
  else count=sscanf(cases[i].text,cases[i].format,&u);
#ifndef INTEGER_INPUT_HOST
  if(errno!=EDOM) return 1;
#endif
  printf("%d %d %u\\n",count,d,u);
 }
 return 0; }
''';path.write_text(code)
    expected=''.join(f'{count} {d if f=="%d" or count!=1 else 123} {u if f!="%d" or count!=1 else 123}\n' for _,f,count,d,u in part).encode();sources.append((path,expected))
atoi_cases=[(prefix+str(n)+'!',n) for n in signed for prefix in ['', ' \t\r\n']]+[('',0),('words',0),('+',0),('--1',0),('010',10)]
path=OUT/'atoi-values.c';path.write_text('#include <stdio.h>\n#include <stdlib.h>\n#include <errno.h>\nstatic const char *cases[]={'+','.join(quote(t) for t,n in atoi_cases)+'};\nint main(void) { unsigned int i; int value; for(i=0;i<sizeof(cases)/sizeof(cases[0]);i++){errno=EDOM;value=atoi(cases[i]);printf("%d %d\\n",value,errno);}return 0;}\n');sources.append((path,''.join(f'{n} 33\n' for t,n in atoi_cases).encode()))
for path,expected in sources:
    executable=path.with_suffix('');run(CC+['-o',executable,path]);r=run([executable]);assert r.stdout==expected and not r.stderr,(path,r.stdout[-300:],expected[-300:])
if host:
    for level in ['-O0','-O2']:
        for path,expected in [(source,b'integer input boundaries passed\n')]+sources:
            executable=OUT/(path.stem+'-host'+level[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-Wno-format-security','-U_FORTIFY_SOURCE','-DINTEGER_INPUT_HOST',level,path,'-o',executable]);r=run([executable]);assert r.stdout==expected and not r.stderr,(level,path,r.stdout[-300:],expected[-300:])
        report['host_oracles'].append(level)
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip()
names=['runtime/gcc-seed/scan.c','runtime/gcc-seed/atoi.c','runtime/gcc-seed/include/stdio.h','runtime/gcc-seed/include/stdlib.h','tests/gcc/integer-input-check.c','tests/gcc/integer-input-check.py'];report['source_sha256']={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names}
report['generated_source_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p,_ in sources}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',len(cases),'scanf cases,',len(atoi_cases),'atoi cases, boundaries/spilled arguments; hostO0/O2:',bool(host));print(OUT/'report.json')
