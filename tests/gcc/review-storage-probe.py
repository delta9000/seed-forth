#!/usr/bin/env python3
"""Independent reconstruction probes. Host compiler only links/checks ABI outcomes."""
from pathlib import Path
import hashlib, json, subprocess, tempfile
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
expected_rejections = {
 'zero-bound':238, 'negative-bound':238, 'overflow-bound':245,
 'typedef-array':238, 'scalar-array-redecl':237, 'array-scalar-redecl':237,
}
work=Path(tempfile.mkdtemp(prefix='sf-review-storage-'))
print('Artifacts:',work,flush=True)
positives = {'extern-order','array-redecl','static-collision','pointer-aggregates','function-pointer-array','static-local-addresses'}
def forth_driver(files,driver):
 data=b''.join((ROOT/f).read_bytes() for f in files)+driver.encode()
 return subprocess.run([str(ROOT/'seed-forth')],input=data,capture_output=True,timeout=15)
start=forth_driver(['010-lib.fth','020-cc-arena.fth','030-cc-io.fth','081-cc-object.fth','122-cc-sysv-runtime.fth'],
 f'create output s, {work}/start.o [lit] 0 c,\ncc-sysrt-start-object output cc-obj-write bye\n')
assert start.returncode==0 and not start.stdout and not start.stderr, start
entry=work/'entry.c'; entry.write_text('int review(void); int main(void){return review();}\n')
subprocess.run([str(ROOT/'tests/gcc/sysv-object-compile.sh'),str(entry),str(work/'entry.o')],cwd=ROOT,check=True,timeout=15)
print('Source hashes:',json.dumps({f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in ['115-cc-native.fth','121-cc-sysv.fth','123-cc-object-program.fth','125-cc-consteval.fth']}),flush=True)
results=[]
for name,source in CASES.items():
 src=work/(name+'.c'); obj=work/(name+'.o'); src.write_text(source+'\n')
 result=subprocess.run([str(ROOT/'tests/gcc/sysv-object-compile.sh'),str(src),str(obj)],cwd=ROOT,text=True,capture_output=True,timeout=15)
 row={'name':name,'compile':result.returncode,'diagnostic':(result.stdout+result.stderr).strip(),'output_exists':obj.exists()}
 if name in positives and result.returncode==0:
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
 if name in positives and result.returncode==0:
  pure=work/(name+'.forth-exe')
  driver=f'''create start-object s, {work}/start.o [lit] 0 c,
create test-object s, {obj} [lit] 0 c,
create entry-object s, {work}/entry.o [lit] 0 c,
create entry-name s, _start
create output s, {pure} [lit] 0 c,
lnk-init start-object lnk-add-object test-object lnk-add-object entry-object lnk-add-object
entry-name [lit] 6 lnk-entry output lnk-link bye
'''
  linked=forth_driver(['010-lib.fth','020-cc-arena.fth','030-cc-io.fth','140-cc-link.fth'],driver)
  row['forth_link']=linked.returncode
  row['forth_diagnostic']=(linked.stdout+linked.stderr).decode(errors='replace').strip()
  if linked.returncode==0 and not linked.stdout and not linked.stderr:
   row['forth_run']=subprocess.run([str(pure)],capture_output=True,timeout=5).returncode
 results.append(row); print(json.dumps(row),flush=True)
(work/'results.json').write_text(json.dumps(results,indent=2)+'\n')

assert all(row.get('run') == 0 and row.get('forth_run') == 0 for row in results if row['name'] in positives), 'positive storage regression'
for row in results:
 if row['name'] in expected_rejections:
  code=expected_rejections[row['name']]
  assert row['compile']==code, f"wrong rejection exit: {row}"
  assert row['diagnostic']==f'cc: line 1: error {code}', f"wrong rejection diagnostic: {row}"
  assert not row['output_exists'], f"rejected translation unit published an object: {row}"
print('PASS: six storage groups through host and Forth executables; six exact diagnostics without object publication')
