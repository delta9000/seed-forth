#!/usr/bin/env python3
"""Pinned original oyacc reconstruction and separate host-reference comparison."""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,signal,subprocess,sys,tempfile,time
ROOT=Path(__file__).resolve().parents[2]
ap=argparse.ArgumentParser();ap.add_argument('source',type=Path);ap.add_argument('--generate-only',action='store_true');args=ap.parse_args()
PIN=json.loads((ROOT/'tests/gcc/oyacc-source.json').read_text());(ROOT/'build-out').mkdir(exist_ok=True);OUT=Path(tempfile.mkdtemp(prefix='oyacc-source-',dir=ROOT/'build-out'));COPY=OUT/'original-source';COPY.mkdir();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for name,digest in PIN['files'].items():
 p=args.source.resolve()/name;assert sha(p)==digest,('source differs',name);shutil.copyfile(p,COPY/name)
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(command,status=0,**kwargs):
 r=subprocess.run([str(x) for x in command],capture_output=True,timeout=120,**kwargs);assert r.returncode==status,(command,r.returncode,r.stdout,r.stderr);return r
identity=run(CC+['--print-source-hash']).stdout.decode().strip();configure=(COPY/'configure').read_text();PROBES=OUT/'probes';PROBES.mkdir();GRAMMAR=ROOT/'tests/gcc/oyacc-arithmetic.y'
probes=['cccheck','deadcheck','dead2check','noreturncheck','prognamecheck','asprintfcheck','pledgecheck','reallocarraycheck','strlcpycheck','wflagcheck']
for name in probes:
 m=re.search(r'\b'+name+r'\(\).*?cat << EOF > conftest.c\n(.*?)\nEOF',configure,re.S);assert m,name;(PROBES/(name+'.c')).write_text(m.group(1)+'\n')
def build(label,compiler):
 directory=OUT/label;directory.mkdir();results={};commands=[];flags=['-D_GNU_SOURCE','-D__unused=']
 for probe in probes:
  cmd=compiler+flags+(['-w'] if probe=='wflagcheck' else [])+['-o',directory/probe,PROBES/(probe+'.c')];r=subprocess.run(list(map(str,cmd)),capture_output=True,timeout=120);(directory/(probe+'.stderr')).write_bytes(r.stderr);results[probe]=r.returncode;commands.append(list(map(str,cmd)))
  if probe=='cccheck':assert r.returncode==0;run([directory/probe])
 config=['/* Results of original configure compile/link probes. */']
 if results['deadcheck']:config.append('#define __dead '+('__dead2' if not results['dead2check'] else '__attribute__((__no_return__))' if not results['noreturncheck'] else ''))
 for probe,macro in [('prognamecheck','HAVE_PROGNAME'),('asprintfcheck','HAVE_ASPRINTF'),('pledgecheck','HAVE_PLEDGE'),('reallocarraycheck','HAVE_REALLOCARRAY'),('strlcpycheck','HAVE_STRLCPY')]:
  if results[probe]==0:config.append('#define '+macro)
 (directory/'config.h').write_text('\n'.join(config)+'\n')
 if results['wflagcheck']==0:flags+=['-w']
 objects=[]
 for source in PIN['translation_units']:
  obj=directory/(Path(source).stem+'.o');cmd=compiler+flags+['-I',directory,'-I',COPY,'-c','-o',obj,COPY/source];r=run(cmd);(directory/(source+'.stderr')).write_bytes(r.stderr);commands.append(list(map(str,cmd)));objects.append(obj)
 executable=directory/'oyacc';cmd=compiler+['-o',executable]+objects;run(cmd);commands.append(list(map(str,cmd)));r=run([executable],status=1);assert b'usage: oyacc ' in r.stderr
 generated=directory/'generated';generated.mkdir();cmd=[executable,'-d','-v','-o','parser.c',GRAMMAR];r=run(cmd,cwd=generated);assert not r.stderr;commands.append(list(map(str,cmd)))
 return {'compiler':list(map(str,compiler)),'probes':results,'commands':commands,'generated_cwd':str(generated),'config_sha256':sha(directory/'config.h'),'generator_sha256':sha(executable),'objects':{p.name:sha(p) for p in objects},'generated':{n:sha(generated/n) for n in ['parser.c','parser.h','y.output']}}
def cleanup_check(executable,ignored):
 directory=OUT/('ignored-cleanup' if ignored else 'signal-cleanup');directory.mkdir();child=None
 def setup():
  if ignored:signal.signal(signal.SIGINT,signal.SIG_IGN)
 try:
  child=subprocess.Popen([str(executable),'-d','-o','parser.c','-'],cwd=directory,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,preexec_fn=setup)
  deadline=time.monotonic()+5
  while True:
   assert child.poll() is None,'oyacc exited before stdin read'
   state=(Path('/proc')/str(child.pid)/'syscall').read_text().split()
   if len(state)>1 and state[0]=='0' and int(state[1],16)==0:break
   assert time.monotonic()<deadline,'oyacc did not reach stdin read';time.sleep(0.005)
  names=[]
  for entry in (Path('/proc')/str(child.pid)/'fd').iterdir():
   try:name=os.readlink(entry)
   except FileNotFoundError:continue
   if name.startswith('/tmp/yacc.'):names.append(Path(name))
  assert len(names)==3,('expected three genuine temporary files',names)
  os.kill(child.pid,signal.SIGINT)
  if ignored:
   time.sleep(0.02);assert child.poll() is None,'inherited SIG_IGN not preserved';stdout,stderr=child.communicate(GRAMMAR.read_bytes(),timeout=10);assert child.returncode==0,(child.returncode,stdout,stderr)
  else:
   stdout,stderr=child.communicate(timeout=10);assert child.returncode==1,(child.returncode,stdout,stderr)
  assert not any(p.exists() for p in names),'oyacc temporary-file cleanup failed'
  return {'temporary_names':len(names),'inherited_ignore':ignored,'status':child.returncode}
 finally:
  if child is not None and child.poll() is None:child.kill();child.communicate(timeout=5)
report={'proof':'original source/configure inputs; Forth production; separate host oracle','compiler_source_identity':identity,'pinned_source':PIN,'grammar_sha256':sha(GRAMMAR),'production':build('production',CC),'consumer_execution':'not_run'}
report['cleanup']=[cleanup_check(OUT/'production/oyacc',False),cleanup_check(OUT/'production/oyacc',True)]
host=shutil.which('gcc')
if host:report['host_reference']=build('host-reference',[host]);assert report['production']['generated']==report['host_reference']['generated'],'generated output mismatch';report['generated_byte_equivalence']=True
if not args.generate_only:
 executable=OUT/'arithmetic-forth';run(CC+['-o',executable,OUT/'production/generated/parser.c'])
 cases=[('2+3*4\n',0,b'14\n',b''),('(2+3)*4\n',0,b'20\n',b''),('-5+2\n',0,b'-3\n',b''),('10/(2+3)\n',0,b'2\n',b''),('16/3\n',0,b'5\n',b''),('1-2-3\n',0,b'-4\n',b''),('12+-5\n',0,b'7\n',b''),('('*350+'7'+')'*350+'\n',0,b'7\n',b''),('1+\n',2,b'',b'parse error\n'),('',2,b'',b'parse error\n')]
 for text,status,stdout,stderr in cases:
  r=run([executable],status=status,input=text.encode());assert (r.stdout,r.stderr)==(stdout,stderr)
 if host:
  oracle=OUT/'arithmetic-host';run([host,'-O2','-o',oracle,OUT/'host-reference/generated/parser.c'])
  for text,status,stdout,stderr in cases:
   r=run([oracle],status=status,input=text.encode());assert (r.stdout,r.stderr)==(stdout,stderr)
 report['consumer_execution']={'cases':len(cases),'forth_executable_sha256':sha(executable),'independent_host_passed':bool(host)}
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip(),'compiler changed during test'
report['test_source_sha256']={n:sha(ROOT/n) for n in ['tests/gcc/oyacc-check.py','tests/gcc/oyacc-source.json','tests/gcc/oyacc-arithmetic.y']};(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: 13 original oyacc TUs, genuine generation, cleanup, independent host match:',bool(host));print('Consumer:',report['consumer_execution']);print(OUT/'report.json')
