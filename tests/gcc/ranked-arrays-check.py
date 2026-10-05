#!/usr/bin/env python3
"""Checked higher-rank array shapes, Forth execution and independent host oracles."""
from pathlib import Path
import argparse,hashlib,json,os,resource,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
POSITIVE={
'pointer-elements': '''int main(void){int x=31;int *a[2][3][4];int *(*p)[3][4]=a;a[1][2][3]=&x;return sizeof a!=192||sizeof *p!=96||*p[1][2][3]!=31;}''',
'function-pointer-elements': '''typedef int (*F)(int);int plus(int n){return n+7;}F a[2][3][4];int main(void){F (*p)[3][4]=a;a[1][2][3]=plus;return sizeof a!=192||p[1][2][3](31)!=38;}''',
'auto-braces': '''int main(void){int a[2][2][2][2]={{{{1,2},{3,4}},{{5,6},{7,8}}},{{{9,10},{11,12}},{{13,14},{15,16}}}};return a[0][0][0][0]!=1||a[1][1][1][1]!=16||a[0][1][1][0]!=7;}''',
'auto-elided': '''int main(void){int a[2][2][2]={1,2,3,4,5};return a[0][0][0]!=1||a[0][1][1]!=4||a[1][0][0]!=5||a[1][1][1]!=0;}''',
'static-braces': '''int a[2][2][2][2]={{{{1,2},{3,4}},{{5,6},{7,8}}},{{{9,10},{11,12}},{{13,14},{15,16}}}};int main(void){return a[0][0][0][0]!=1||a[1][1][1][1]!=16||a[0][1][1][0]!=7;}''',
'static-elided': '''int a[2][2][2]={1,2,3,4,5};int main(void){return a[0][0][0]!=1||a[0][1][1]!=4||a[1][0][0]!=5||a[1][1][1]!=0;}''',
'string-rows': '''char a[2][2][4]={{"ab","cd"},{"ef","g"}};int main(void){char b[2][2][4]={{"hi","j"},{"kl","m"}};return sizeof a!=16||a[1][0][1]!='f'||a[1][1][1]!=0||b[1][0][1]!='l'||b[1][1][1]!=0;}''',
'inferred-outer': '''int a[][2][2]={{{1,2},{3,4}},{{5,6},{7,8}}};int main(void){return sizeof a!=32||a[1][1][1]!=8;}''',
'static-addresses': '''unsigned a[2][3][2][4];unsigned *p=&a[1][2][1][3];unsigned (*r)[4]=&a[1][2][1];unsigned (*q)[2][4]=&a[1][2];unsigned (*s)[3][2][4]=a;unsigned (*w)[2][3][2][4]=&a;int main(void){a[1][2][1][3]=47;return *p!=47||(*r)[3]!=47||(*q)[1][3]!=47||s[1][2][1][3]!=47||(*w)[1][2][1][3]!=47;}''',
'pointer-operations': '''int main(void){long a[2][3][4];long (*p)[3][4]=a;long (*q)[3][4]=p+1;long (*r)[3][4]=1?p:q;long (**pp)[3][4]=&p;(*pp)++;if(p!=q||q-r!=1)return 1;--p;p+=1;p-=1;return p!=r||sizeof **pp!=96;}''',
'parameter-decay': '''int sum(int a[][2][3]){return a[0][0][0]+a[1][1][2];}int main(void){int a[2][2][3]={{{1,2,3},{4,5,6}},{{7,8,9},{10,11,12}}};return sum(a)!=13;}''',
'qualified-reads': '''const int a[2][2][2]={{{1,2},{3,4}},{{5,6},{7,8}}};struct S{volatile int a[2][2][2];};int main(void){struct S s;s.a[1][1][1]=31;return a[1][1][1]!=8||sizeof a!=32||s.a[1][1][1]!=31;}''',
'record-alignment': '''struct S{char c;short a[2][2][2];char d;};struct S s={1,{{{2,3},{4,5}},{{6,7},{8,9}}},10};int main(void){struct S t={11,{{{12,13},{14,15}},{{16,17},{18,19}}},20};return sizeof s!=20||s.a[1][1][1]!=9||s.d!=10||t.a[1][1][1]!=19||t.d!=20||(char*)&s.a-(char*)&s!=2;}''',
'record-elements': '''struct E{char c;long n;};struct E a[1][2][2]={{{{1,2},{3,4}},{{5,6},{7,8}}}};int main(void){struct E b[1][2][2]={{{{11,12},{13,14}},{{15,16},{17,18}}}};return sizeof a!=64||a[0][1][1].n!=8||b[0][1][1].n!=18;}''',
'array-typedef': '''typedef int Cube[2][3][4];Cube a;Cube *p=&a;typedef Cube Alias;Alias b;int main(void){a[1][2][3]=29;b[1][2][3]=31;return sizeof(Cube)!=96||sizeof(Alias)!=96||(*p)[1][2][3]!=29||b[1][2][3]!=31;}''',
'equivalent-spellings': '''typedef int Matrix[3][4];int a[2][3][4];int f(int (*p)[3][4]){return p[1][2][3];}int main(void){int (*p)[3][4]=a;Matrix *q=a;a[1][2][3]=77;return f(q)!=77||q!=p||sizeof *q!=48;}''',
'exact-limit': '''struct S { char a[1024][1024][1024]; };int main(void){return sizeof(struct S)!=1073741824UL;}''',
'one-past-static': '''int a[2][3][4];int (*p)[3][4]=&a[2];int (*q)[4]=&a[1][3];int *r=&a[1][2][4];int main(void){return p-a!=2||q-a[1]!=3||r-a[1][2]!=4;}''',
'composed-rank64': 'typedef char A'+'[1]'*63+';A b[1];int main(void){b'+'[0]'*64+'=23;return sizeof b!=1||b'+'[0]'*64+'!=23;}',
'rank64': 'char a'+'[1]'*64+';int main(void){a'+'[0]'*64+'=37;return sizeof a!=1||a'+'[0]'*64+'!=37;}',
'qualified-parameters': '''typedef int A[2][3][4];int sum(const int a[][2][3]){return a[0][0][0]+a[1][1][2];}int vsum(volatile int a[][2][3][4]){return a[1][1][2][3];}int tsum(const A a){return a[1][2][3];}const int c[2][2][3]={{{1,2,3},{4,5,6}},{{7,8,9},{10,11,12}}};volatile int v[2][2][3][4];const A t={{{0}},{{0},{0},{0,0,0,9}}};int main(void){const int (*p)[2][3]=c;const int (*q)[2][2][3]=&c;v[1][1][2][3]=5;return sum(c)!=13||sum(p+0)!=13||(*q)[1][1][2]!=12||vsum(v)!=5||tsum(t)!=9||p+1!=&c[1];}''',
}
REJECT={
'float-record-value':('struct F{float a[1][1][1];};struct F f(struct F a){return a;}',232),
'double-record-value':('struct F{double a[1][1][1];};struct F f(struct F a){return a;}',232),
'long-double-record-value':('struct F{long double a[1][1][1];};struct F f(struct F a){return a;}',232),
'inferred-unbraced':('int a[][2][3]={1,2,3,4,5,6,7};',222),
'inferred-unbraced-local':('int main(void){int a[][2][3]={1,2,3,4,5,6,7};return sizeof a;}',222),
'grouped-function-pointer-array':('int (*callbacks[2][3][4])(int);',238),
'grouped-function-pointer-field':('struct S{int (*callbacks[2][3][4])(int);};',238),
'grouped-pointer-array':('int (*p[2][3][4]);',238),
'zero-third':('int a[2][3][0];',238),'negative-fourth':('int a[2][3][4][-1];',238),
'zero-first':('int a[0][2][3];',238),'zero-second':('int a[2][0][3];',238),
'huge-third':('long a[2][3][9223372036854775807L];',245),
'product-overflow':('long a[1024][1024][1024];',245),
'qualified-decay':('const int a[2][3][4];int (*p)[3][4]=a;',238),
'qualified-address':('const int a[2][3][4];int (*p)[2][3][4]=&a;',238),
'array-assign':('int a[2][3][4],b[2][3][4];void f(void){a=b;}',120),
'row-assign':('int a[2][3][4],b[2][3][4];void f(void){a[0]=b[0];}',120),
'array-increment':('int a[2][3][4];void f(void){a++;}',113),
'extra-subscript':('int a[2][3][4];int f(void){return a[1][2][3][0];}',238),
'row-bound-mismatch':('int a[2][3][4];int (*p)[3][5]=a;',237),
'row-element-mismatch':('int a[2][3][4];long (*p)[3][4]=a;',237),
'row-rank-mismatch':('int a[2][3][4];int (*p)[12]=a;',237),
'redecl-shape':('extern int a[2][3][4];int a[2][4][3];',237),
'redecl-record':('struct S{int a;};struct T{int a;};extern struct S a[2][3][4];struct T a[2][3][4];',237),
'excess-initializer':('int a[1][1][1]={{{1,2}}};',226),
'static-bound':('int a[2][3][4];int *p=&a[1][2][5];',240),
'rank65':('char a'+'[1]'*65+';',238),
'composed-rank65':('typedef char A'+'[1]'*64+';A b[1];',238),
'grouped-rank65':('char (*p)'+'[1]'*65+';',238),
}
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--work',type=Path);a=ap.parse_args()
 resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
 work=(a.work or Path(tempfile.mkdtemp(prefix='ranked-arrays-',dir=ROOT/'build-out'))).resolve();work.mkdir(parents=True,exist_ok=True)
 events=[];env=dict(os.environ,LC_ALL='C',PYTHONWARNINGS="ignore:'maxsplit' is passed as positional argument:DeprecationWarning")
 def run(cmd,expected=0):
  cmd=list(map(str,cmd));p=subprocess.run(cmd,capture_output=True,timeout=180,env=env)
  events.append(dict(command=cmd,status=p.returncode,stdout=p.stdout.decode(errors='replace'),stderr=p.stderr.decode(errors='replace')))
  (work/'commands.json').write_text(json.dumps(events,indent=2)+'\n')
  assert p.returncode==expected,events[-1]
  return p.stdout
 cc=[sys.executable,ROOT/'tools/gcc-direct-cc.py'];before=run(cc+['--print-source-hash']).decode().strip()
 for name,source in POSITIVE.items():
  src=work/(name+'.c');src.write_text(source+'\n');obj=work/(name+'.o');exe=work/name
  run(cc+['-c',src,'-o',obj]);run(['gcc','-no-pie','-Wl,-z,noexecstack',obj,'-o',exe]);run([exe])
  for opt in ('-O0','-O2'):
   host=work/(name+opt);run(['gcc','-std=c90','-pedantic-errors',opt,src,'-o',host]);run([host])
 for name,(source,code) in REJECT.items():
  src=work/(name+'.c');src.write_text(source+'\n');out=work/(name+'.o');out.write_bytes(b'preserve existing output\n')
  run(cc+['-c',src,'-o',out],code);assert out.read_bytes()==b'preserve existing output\n'
 fixtures=[ROOT/'tests/gcc'/('ranked-arrays-'+n+'.c') for n in ('provider','main')];objs=[work/(n+'.o') for n in ('provider','main')]
 for src,obj in zip(fixtures,objs):run(cc+['-c',src,'-o',obj])
 for opt in ('-O0','-O2'):
  hosts=[work/(n+opt+'.o') for n in ('provider','main')]
  for src,obj in zip(fixtures,hosts):run(['gcc','-std=c90','-pedantic-errors',opt,'-fno-pie','-fno-stack-protector','-c',src,'-o',obj])
  for label,parts in [('host',hosts),('forth-provider',[objs[0],hosts[1]]),('forth-main',[hosts[0],objs[1]]),('forth-objects',objs)]:
   exe=work/(label+opt);run(['gcc','-no-pie','-Wl,-z,noexecstack',*parts,'-o',exe]);run([exe])
 exe=work/'forth-only';run(cc+objs+['-o',exe]);run([exe])
 after=run(cc+['--print-source-hash']).decode().strip();assert before==after
 (work/'result.json').write_text(json.dumps({'compiler_identity':before,'positive_programs':len(POSITIVE),'negative_programs':len(REJECT),'commands':len(events),'status':'passed','source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in fixtures}},indent=2)+'\n')
 print((work/'result.json').read_text())
if __name__=='__main__':main()
