#!/usr/bin/env python3
"""Shared SysV binary64 argument plan; host tools are independent ABI oracles."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
TEST=ROOT/'tests/gcc'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(command, status=0, data=None):
 p=subprocess.run([str(x) for x in command],input=data,capture_output=True,timeout=120)
 assert p.returncode==status,(command,p.returncode,p.stdout,p.stderr)
 return p

def main():
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument('--source-root',type=Path);ap.add_argument('--baseline-root',type=Path)
 ap.add_argument('--work',type=Path);a=ap.parse_args()
 (ROOT/'build-out').mkdir(exist_ok=True)
 work=a.work or Path(tempfile.mkdtemp(prefix='binary64-arguments-',dir=ROOT/'build-out'))
 work=work.resolve();work.mkdir(parents=True,exist_ok=True)
 inputs=[ROOT/'seed-forth',ROOT/'010-lib.fth',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),ROOT/'tools/gcc-direct-cc.py',*sorted(TEST.glob('binary64-arguments*'))]
 hashes={str(p.relative_to(ROOT)):sha(p) for p in inputs if p.is_file()}
 report={'compiler_and_test_sha256':hashes,'executions':[],'rejections':{},'preservation':[]}
 cc=ROOT/'tools/gcc-direct-cc.py'
 provider=work/'host-provider.c';provider.write_text((TEST/'binary64-arguments-provider.c').read_text().replace('seed_','host_')+'\ndouble host_apply(double (*p)(double),double x){return p(x)+p(x+1.0);}\n')
 al_c=work/'al-production.c';al_c.write_text('long host_al(long n,...){return n;}\n')
 pobj=work/'provider.o';cobj=work/'caller.o'
 run([cc,'-c',TEST/'binary64-arguments-provider.c','-o',pobj]);run([cc,'-c',TEST/'binary64-arguments-caller.c','-o',cobj])
 exe=work/'production';run([cc,'-I'+str(TEST),pobj,cobj,provider,al_c,TEST/'binary64-arguments-main.c','-o',exe]);run([exe])
 report['executions'].append({'name':'Forth-only separate objects','sha256':sha(exe),'al_observation':False})
 mapped=work/'mapped.c';mapped.write_text('\n'.join('#include "'+str(p)+'"' for p in [TEST/'binary64-arguments-provider.c',TEST/'binary64-arguments-caller.c',provider,al_c,TEST/'binary64-arguments-main.c'])+'\n')
 exe=work/'mapped';run([TEST/'sysv-compile.sh',mapped,exe,TEST,ROOT/'runtime/gcc-seed/include']);run([exe]);report['executions'].append({'name':'Forth-only mapped ELF','sha256':sha(exe),'al_observation':False})
 print('PASS: Forth-only independent GP/XMM banks, overflow, variadics, nesting, callbacks and aggregate coexistence',flush=True)
 for opt in ('-O0','-O2'):
  exe=work/('interop'+opt);run(['gcc',opt,'-fno-builtin','-fno-pie','-no-pie','-I'+str(TEST),TEST/'binary64-arguments-main.c',provider,TEST/'binary64-arguments-al.S',pobj,cobj,'-o',exe]);run([exe])
  report['executions'].append({'name':'host inbound/outbound '+opt,'sha256':sha(exe),'al_observation':True})
 print('PASS: host O0/O2 inbound/outbound ABI, exact %al count and 16-byte call alignment',flush=True)
 # Integer and binary64 arguments convert to extended values before copying.
 for name,body in {
  "extended-call":"void f(long double);void g(void){f(1);}",
  "extended-from-double":"void f(long double);void g(double x){f(x);}",
 }.items():
  src=work/(name+".c");src.write_text(body+"\n")
  run([cc,"-c",src,"-o",work/(name+".o")])
 rejects={
  'floating-record':'struct A{double x;};void f(struct A x){}',
  'too-many':'void f(double);void g(void){f(1.0,2.0);}',
  'too-few':'void f(double,double);void g(void){f(1.0);}',
 }
 for name,body in rejects.items():
  src=work/(name+'.c');src.write_text(body+'\n');out=work/(name+'.o');status=235 if name.startswith('too-') else 232
  for existing in (False,True):
   out.unlink(missing_ok=True)
   if existing:out.write_bytes(b'previous-object\x00\xff')
   p=run([cc,'-c',src,'-o',out],status)
   assert ('error '+str(status)).encode() in p.stderr
   assert out.read_bytes()==b'previous-object\x00\xff' if existing else not out.exists()
  report['rejections'][name]=status
 # INTEGER records mix with binary64 in variadic plans (record-varargs-check.py).
 accepts={
  'aggregate-vararg':'struct A{long x;};void f(int,...);void g(void){struct A x;f(0,x);}',
  'aggregate-variadic-fixed':'struct A{long x;};void f(struct A x,double y,...){}',
  'aggregate-variadic-result':'struct A{long x;};struct A f(double x,...){}',
 }
 for name,body in accepts.items():
  src=work/(name+'.c');src.write_text(body+'\n');run([cc,'-c',src,'-o',work/(name+'.o')])
 # A shared scalar plan must fit thousands of ordinary calls in the 8 MiB arena.
 src=work/'many-calls.c';src.write_text('double f(double x){return x;}int main(void){'+'f(1.0);'*2000+'return 0;}\n')
 exe=work/'many-calls';run([cc,src,'-o',exe]);run([exe]);report['executions'].append({'name':'2000 fixed-prototype plans in default arena','sha256':sha(exe)})
 # The 64-argument bound applies to the complete mixed-bank plan.
 src=work/'too-many-total.c';src.write_text('void f(int,...);void g(void){f('+','.join(['0']*65)+');}\n')
 run([cc,'-c',src,'-o',work/'too-many-total.o'],234);assert not (work/'too-many-total.o').exists()
 report['rejections']['too-many-total']=234
 if a.source_root:
  source=a.source_root/'gcc/genautomata.c';text=source.read_text()
  assert sha(source)=='10c094d41d86176e63812328723062a14a3d6f0fbc1e082ad7890b78dab868ae'
  start=text.index('static double\nestimate_one_automaton_bound (void)');end=text.index('\n}',start)+2;body=text[start:end]
  prelude='''struct unit {int max_occ_cycle_num;int min_occ_cycle_num;};
struct declaration {int mode;struct unit unit;};typedef struct declaration *decl_t;
struct description {int decls_num;decl_t *decls;};
struct description *description;int automata_num;
#define DECL_UNIT(d) (&(d)->unit)
#define dm_unit 1
#define MAX_FLOATING_POINT_VALUE_FOR_AUTOMATON_BOUND 1.0E37
/* Deliberate ABI-only test shims, not production math implementations. */
double log(double x){return x*2.0;}double exp(double x){return x+1.0;}
'''
  tail='''\nint main(void){struct declaration a={1,{4,1}},b={1,{9,2}};decl_t ds[2];struct description desc;
ds[0]=&a;ds[1]=&b;desc.decls_num=2;desc.decls=ds;description=&desc;automata_num=2;
return estimate_one_automaton_bound()!=45.0;}\n'''
  selected=work/'original-genautomata-function.c';selected.write_text(prelude+body+tail)
  exe=work/'original-function';run([cc,selected,'-o',exe]);run([exe])
  report['original_source']={'sha256':sha(source),'exact_function_body_sha256':hashlib.sha256(body.encode()).hexdigest(),'selection_sha256':sha(selected),'scope':'Exact estimate_one_automaton_bound body, reduced metadata and explicit ABI-only exp/log shims; not complete genautomata or production math'}
  print('PASS: exact original genautomata nested exp(log(...)) function body with explicit ABI-only math shims',flush=True)
 if a.baseline_root:
  layers=[ROOT/'010-lib.fth',*sorted(p for p in ROOT.glob('[0-9][0-9][0-9]-cc-*.fth') if p.name not in ('120-cc-main.fth','140-cc-link.fth'))]
  vocab=[b'\n'.join((base/p.relative_to(ROOT)).read_bytes() for p in layers) for base in (a.baseline_root,ROOT)]
  for name in ['basics','layout','stack-call','literals','many-args','switch-goto']:
   src=(TEST.parent/'tcc'/('native-'+name+'.c')).read_bytes()
   script=b'true cc-target-lp64 ! true cc-prep-direct ! [lit] 8388608 cc-arena-map\n: go cc-load-stdin cc-preprocess cc-out-init cc-globals-init cc-emit-elf-header cc-native-program cc-finalize-globals cc-finalize-elf [lit] 1 cc-out-buf cc-out-pos @ write drop bye ;\ngo\n'
   outputs=[run([ROOT/'seed-forth'],data=v+b'\n'+script+src).stdout for v in vocab]
   assert outputs[0]==outputs[1],name
   report['preservation'].append({'case':name,'bytes':len(outputs[0]),'sha256':hashlib.sha256(outputs[0]).hexdigest()})
  print('PASS: native/TinyCC-profile ELF bytes identical to accepted baseline on six fixtures',flush=True)
 assert hashes=={str(p.relative_to(ROOT)):sha(p) for p in inputs if p.is_file()},'inputs changed during proof'
 (work/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(work/'report.json')
if __name__=='__main__':main()
