#!/usr/bin/env python3
"""Independent reconstruction probes. Host compiler only links/checks ABI outcomes."""
from pathlib import Path
import json, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[2]
CASES = {
 'extern-order': '''extern int before; int read_before(void){return before;} int before=17; extern int before; int before;
 int after=25; extern int after; int after; int review(void){return read_before()+after==42?0:1;}''',
 'array-redecl': '''extern int a[]; extern int a[3]; int a[3]={9,10,23}; extern int a[]; int a[3];
 int review(void){return sizeof(a)==12&&a[0]+a[1]+a[2]==42?0:1;}''',
 'static-collision': '''int value=100; int first(void){static int value=7; return ++value;} int second(void){static int value; return ++value;}
 int blocks(int x){if(x){static int value=10;return ++value;}else{static int value=20;return ++value;}}
 int review(void){if(first()!=8||second()!=1||first()!=9||second()!=2)return 1; if(blocks(1)!=11||blocks(0)!=21||blocks(1)!=12||blocks(0)!=22)return 2;return value==100?0:3;}''',
 'pointer-aggregates': '''int values[4]={10,20,30,40}; int *pointers[3]={values,&values[2],values+3};
 struct S { char tag; int *p; long count; }; struct S objects[2]={{1,values+1,7},{2,&values[3],9}};
 char *texts[2]={"abc","def"};
 int review(void){if(*pointers[0]!=10||*pointers[1]!=30||*pointers[2]!=40)return 1; if(objects[0].tag!=1||*objects[0].p!=20||objects[1].count!=9)return 2;return texts[1][2]=='f'?0:3;}''',
 'function-pointer-array': '''int inc(int x){return x+1;} int twice(int x){return x*2;} typedef int (*Fn)(int); Fn callbacks[2]={inc,twice};
 int review(void){return callbacks[0](20)+callbacks[1](10)==41?0:1;}''',
 'static-local-addresses': '''int one(void){static int a[2]={4,9}; static int *p=&a[1]; return ++*p;} int two(void){static int a[2]={6,19}; static int *p=a+1; return ++*p;}
 int review(void){return one()==10&&two()==20&&one()==11&&two()==21?0:1;}''',
 'zero-bound': 'int zero[0]; int review(void){return sizeof(zero)==0?0:1;}',
 'negative-bound': 'int negative[-2]; int review(void){return sizeof(negative)==4?0:1;}',
 'overflow-bound': 'long overflow[2305843009213693953UL]; int review(void){return sizeof(overflow)==8?0:1;}',
 'typedef-array': 'typedef int A[3]; A a; int review(void){return sizeof(a)==12?0:1;}',
 'scalar-array-redecl': 'int a; extern int a[3]; int review(void){return sizeof(a)==12?0:1;}',
 'array-scalar-redecl': 'int a[3]={1,2,3}; extern int a; int review(void){return sizeof(a)==4?0:1;}',
}
work=Path(tempfile.mkdtemp(prefix='sf-review-storage-'))
print('Artifacts:',work,flush=True)
results=[]
for name,source in CASES.items():
 src=work/(name+'.c'); obj=work/(name+'.o'); src.write_text(source+'\n')
 result=subprocess.run([str(ROOT/'tests/gcc/sysv-object-compile.sh'),str(src),str(obj)],cwd=ROOT,text=True,capture_output=True,timeout=15)
 row={'name':name,'compile':result.returncode,'diagnostic':(result.stdout+result.stderr).strip()}
 if result.returncode==0:
  syms=subprocess.run(['readelf','-sW',str(obj)],text=True,capture_output=True)
  (work/(name+'.symbols')).write_text(syms.stdout)
  host=work/'host.c'; host.write_text('int review(void); int main(void){return review();}\n')
  exe=work/(name+'.exe')
  link=subprocess.run(['cc','-O2','-fno-pie','-no-pie',str(host),str(obj),'-o',str(exe)],text=True,capture_output=True)
  row['link']=link.returncode
  if link.returncode==0:
   run=subprocess.run([str(exe)],text=True,capture_output=True,timeout=5)
   row['run']=run.returncode
  else: row['link_diagnostic']=link.stderr.strip()
 results.append(row); print(json.dumps(row),flush=True)
(work/'results.json').write_text(json.dumps(results,indent=2)+'\n')
