#!/usr/bin/env python3
"""Record conditional snapshots, non-lvalues, omitted for metadata and cross ABI.

Host compilers are independent test oracles only. Production objects are Forth.
Optional original-source checks are explicit reductions, not complete TU proof.
"""
import argparse, hashlib, json, os, resource, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
TEST=ROOT/'tests/gcc'
CC=ROOT/'tools/gcc-direct-cc.py'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-root',type=Path)
args=parser.parse_args()
(ROOT/'build-out').mkdir(exist_ok=True)
W=Path(tempfile.mkdtemp(prefix='libcpp-expression-',dir=ROOT/'build-out'))
report={'scope':'Focused conditional/for regression, no host production tools', 'checks':[]}
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def bounded(): resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3))
def run(name,cmd,expected=0):
 p=subprocess.run(list(map(str,cmd)),cwd=ROOT,capture_output=True,timeout=180,preexec_fn=bounded)
 (W/(name+'.stdout')).write_bytes(p.stdout);(W/(name+'.stderr')).write_bytes(p.stderr)
 report['checks'].append({'name':name,'returncode':p.returncode,'expected':expected})
 (W/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 assert p.returncode==expected,(name,p.returncode,expected,p.stderr.decode(errors='replace'))
 return p
inputs=[ROOT/'seed-forth',ROOT/'010-lib.fth',*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')),CC,*sorted(TEST.glob('libcpp-expression*'))]
report['inputs']={str(p.relative_to(ROOT)):sha(p) for p in inputs if p.is_file()}
report['compiler_identity']=run('identity',[CC,'--print-source-hash']).stdout.decode().strip()
source=TEST/'libcpp-expression.c';obj=W/'semantics.o';exe=W/'semantics'
run('forth-object',[CC,'-c',source,'-o',obj]);run('forth-link',[CC,obj,'-o',exe]);run('forth-execute',[exe])
for opt in ('-O0','-O2'):
 for origin,files in [('host-source',[source]),('host-link-forth',[obj])]:
  exe=W/(origin+opt);run(origin+opt,['cc','-std=c11','-pedantic-errors',opt,'-fno-pie','-no-pie',*files,'-o',exe]);run(origin+opt+'-execute',[exe])
print('PASS: branch effects, nested array snapshots, non-lvalue reads, unions, local floating records and for metadata',flush=True)
for size in (1,7,8,9,15,16,17,33):
 d=W/f'abi-{size}';d.mkdir()
 header=f'struct R{{unsigned char x[{size}];}};\n'
 signature='(int n,struct R a,struct R b)'
 body='{return n?a:b;}\n'
 src=d/'production.c';src.write_text(header+'struct R host_choose'+signature+';\nstruct R sf_choose'+signature+body+'struct R sf_outbound'+signature+'{return host_choose(n,a,b);}\n')
 host=d/'host.c';host.write_text(header+'struct R sf_choose'+signature+';\nstruct R sf_outbound'+signature+';\nstruct R host_choose'+signature+body+f'''int main(void){{struct R a,b,c;int i,n;for(i=0;i<{size};i++){{a.x[i]=i+3;b.x[i]=i+71;}}for(n=0;n<2;n++){{c=sf_choose(n,a,b);for(i=0;i<{size};i++)if(c.x[i]!=(n?a.x[i]:b.x[i]))return 1;c=sf_outbound(n,a,b);for(i=0;i<{size};i++)if(c.x[i]!=(n?a.x[i]:b.x[i]))return 2;}}return 0;}}\n''')
 obj=d/'production.o';run(f'abi-{size}-object',[CC,'-c',src,'-o',obj])
 for opt in ('-O0','-O2'):
  exe=d/opt;run(f'abi-{size}{opt}-link',['cc',opt,'-fno-pie','-no-pie',host,obj,'-o',exe]);run(f'abi-{size}{opt}-execute',[exe])
print('PASS: both directions of INTEGER/MEMORY ABI, sizes 1/7/8/9/15/16/17/33 at host O0/O2',flush=True)
neg={
 'different-record':(232,'struct A{int x;};struct B{int x;};void f(int c){struct A a;struct B b;(void)(c?a:b);}'),
 'record-scalar':(232,'struct A{int x;};void f(int c){struct A a;(void)(c?a:0);}'),
 'scalar-record':(232,'struct A{int x;};void f(int c){struct A a;(void)(c?0:a);}'),
 'sizeof-different':(232,'struct A{int x;};struct B{int x;};int f(int c){struct A a;struct B b;return sizeof(c?a:b);}'),
 'assign-result':(120,'struct A{int x;};void f(int c){struct A a,b;(c?a:b)=a;}'),
 'address-result':(116,'struct A{int x;};void f(int c){struct A a,b;(void)&(c?a:b);}'),
 'address-array-member':(116,'struct A{int x[2];};void f(int c){struct A a,b;(void)&(c?a:b).x;}'),
 'sizeof-address-array-member':(116,'struct A{int x[2];};int f(int c){struct A a,b;return sizeof(&(c?a:b).x);}'),
 'assign-member':(120,'struct A{int x;};void f(int c){struct A a,b;(c?a:b).x=1;}'),
 'address-member':(116,'struct A{int x;};void f(int c){struct A a,b;(void)&(c?a:b).x;}'),
 'increment-member':(113,'struct A{int x;};void f(int c){struct A a,b;(c?a:b).x++;}'),
 'nested-assign-member':(120,'struct A{int x;};struct B{struct A a;};void f(int c){struct B a,b;(c?a:b).a.x=1;}'),
 'nested-address-record':(116,'struct A{int x;};struct B{struct A a;};void f(int c){struct B a,b;(void)&(c?a:b).a;}'),
 'for-record':(232,'struct A{int x;};void f(void){struct A a;for(;a;)break;}'),
 'for-record-assignment':(232,'struct A{int x;};void f(void){struct A a,b;for(;a=b;)break;}'),
 'for-record-conditional':(232,'struct A{int x;};void f(int c){struct A a,b;for(;c?a:b;)break;}'),
 'if-record':(232,'struct A{int x;};void f(int c){struct A a,b;if(c?a:b)return;}'),
}
for name,(code,text) in neg.items():
 src=W/(name+'.c');src.write_text(text+'\n');out=W/(name+'.o')
 for existing in (False,True):
  out.unlink(missing_ok=True)
  if existing: out.write_bytes(b'previous-object\x00\xff')
  run(name+str(existing),[CC,'-c',src,'-o',out],code)
  assert out.read_bytes()==b'previous-object\x00\xff' if existing else not out.exists()
print(f'PASS: {len(neg)} negative forms preserve existing and absent outputs',flush=True)
if args.source_root:
 srcroot=args.source_root.resolve()
 pins=json.loads((TEST/'libcpp-expression-source-pins.json').read_text())
 assert {name:sha(srcroot/name) for name in pins}==pins
 header=(srcroot/'libcpp/internal.h').read_text();charset=(srcroot/'libcpp/charset.c').read_text();macro=(srcroot/'libcpp/macro.c').read_text()
 descriptor=header[header.index('typedef bool (*convert_f)'):header.index('\n#define BITS_PER_CPPCHAR_T')]
 selection='  struct cset_converter cvt\n    = wide ? pfile->wide_cset_desc : pfile->narrow_cset_desc;'
 assert charset.count(selection)==3
 assert '      *token = *ctoken;\n    }\n\n  for (;;)' in macro
 reduction=W/'original-derived.c'
 reduction.write_text('typedef int bool; typedef int iconv_t; typedef unsigned long size_t; struct _cpp_strbuf;\n'+descriptor+'''\nstruct reader {struct cset_converter wide_cset_desc,narrow_cset_desc;};
static struct cset_converter choose(struct reader *pfile,int wide){
'''+selection+'''
return cvt;}
static int scan(void){struct cset_converter a={0,17},b={0,29};struct cset_converter *token=&a,*ctoken=&b;
      *token = *ctoken;
  for (;;) {return token->cd;}}
int main(void){struct reader r={{0,31},{0,47}};struct cset_converter a=choose(&r,1),b=choose(&r,0);return a.cd!=31||b.cd!=47||scan()!=29;}
''')
 exe=W/'original-derived';run('original-derived-forth',[CC,reduction,'-o',exe]);run('original-derived-forth-execute',[exe])
 for opt in ('-O0','-O2'):
  exe=W/('original-derived'+opt);run('original-derived'+opt,['cc',opt,reduction,'-o',exe]);run('original-derived'+opt+'-execute',[exe])
 report['original_reductions']={'pins':pins,'reduction_sha256':sha(reduction),'selection_occurrences':3,'scope':'Exact descriptor, three identical selection statements and record-copy/for sequence; surrounding harness is synthetic'}
 assert {name:sha(srcroot/name) for name in pins}==pins
 print('PASS: original-derived libcpp descriptor/conditional and record-copy/for reductions',flush=True)
assert report['inputs']=={name:sha(ROOT/name) for name in report['inputs']}
report['seed_bytes']=(ROOT/'seed-forth').stat().st_size
assert report['seed_bytes']==1772
(W/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(W/'report.json')
