#!/usr/bin/env python3
"""Percent-conversion whitespace versus strict ordinary scanf literals."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='scanf-percent-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(args):
    r=subprocess.run(list(map(str,args)),capture_output=True,timeout=120)
    assert r.returncode==0,(args,r.returncode,r.stdout[-300:],r.stderr)
    return r
def quote(text):return '"'+''.join('\\%03o'%ord(c) for c in text)+'"'
cases=[]
def add(text,format,count,first=77,second=88,third=99):
    cases.append((text,format,count,first,second,third))
for space in ['', ' ', '\t', '\n', '\r', '\v', '\f', ' \t\n\r\v\f']:
    add(space+'%42','%%%d',1,42)
    add('7'+space+'%42','%d%%%d',2,7,42)
    add(space+'%x42','%%x%d',1,42)
    add(space+'% x42','%%x%d',0)
for text in ['', ' ', '\t\n']:
    add(text,'%%',-1)
    add(text,'%%%d',-1)
    add('7'+text,'%d%%%d',1,7)
for text in ['!', ' \t!', ' %x', ' %%42']:
    add(text,'%%%d',0)
add('%','%%',0)
add(' \t%','%%',0)
add('%','%%%d',-1)
add('% \t','%%%d',-1)
add('% +','%%%d',0)
add('% -','%%%d',0)
add('7%','%d%%%d',1,7)
add('7 % q','%d%%%d',1,7)
add('7 \t!','%d%%%d',1,7)
add(' % x42','%% x%d',1,42)
add('%x','%%x%d',-1)
add(' % \t%42','%%%%%d',1,42)
add('% %','%%%%%d',-1)
add(' X42','X%d',0)
add('X \t42','X%d',1,42)
add(' X42',' X%d',1,42)
add('X','X%d',-1)
add('','X%d',-1)
add(' \t','X%d',0)
add('%x 42','%%x%d',1,42)
add('% x 42','%%x%d',0)
add('4 %5 %6','%d%%%d%%%d',3,4,5,6)
add('4 %5 !6','%d%%%d%%%d',2,4,5)
source=OUT/'percent-cases.c'
source.write_text('#include <stdio.h>\nstruct item { const char *text; const char *format; };\nstatic struct item cases[]={\n'+''.join('{'+quote(t)+','+quote(f)+'},\n' for t,f,_,_,_,_ in cases)+'''};
int main(void) {
    unsigned int i;
    int first,second,third,count;
    for(i=0;i<sizeof(cases)/sizeof(cases[0]);i++) {
        first=77;second=88;third=99;
        count=sscanf(cases[i].text,cases[i].format,&first,&second,&third);
        printf("%d %d %d %d\\n",count,first,second,third);
    }
    return 0;
}
''')
expected=''.join(f'{n} {a} {b} {c}\n' for _,_,n,a,b,c in cases).encode()
def check(executable):
    r=run([executable]);actual=r.stdout.splitlines();wanted=expected.splitlines()
    for i,(left,right) in enumerate(zip(actual,wanted)):
        assert left==right,(executable.name,i,cases[i],left,right)
    assert r.stdout==expected and not r.stderr,(executable.name,r.stdout[-300:],r.stderr)
    return hashlib.sha256(r.stdout).hexdigest()
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
production=OUT/'production';run(CC+['-o',production,source])
report={'compiler_source_identity':identity,'focused_cases':len(cases),'production_output_sha256':check(production),'host_oracles':{}}
host=shutil.which('gcc')
if host:
    for level in ['-O0','-O2']:
        executable=OUT/('host'+level[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror',level,source,'-o',executable]);report['host_oracles'][level]=check(executable)
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip()
names=['runtime/gcc-seed/scan.c','tests/gcc/scanf-percent-check.py'];report['source_sha256']={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names};report['fixture_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS:',len(cases),'percent-conversion/literal/EOF/count cases; host O0/O2:',bool(host));print(OUT/'report.json')
