#!/usr/bin/env python3
"""Real-kernel signal contract; separately compile host-header/libc oracles."""
from pathlib import Path
import hashlib,json,os,resource,selectors,shutil,signal,subprocess,sys,tempfile,time
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='signal-check-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
SOURCE=ROOT/'tests/gcc/signal-check.c'
def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
def run(args):
 return subprocess.run([str(x) for x in args],capture_output=True,timeout=120,preexec_fn=no_core)
def checked(args):
 r=run(args)
 assert r.returncode==0,(args,r.returncode,r.stdout,r.stderr)
 return r
def waiting_read(process,fd):
 deadline=time.monotonic()+5
 while time.monotonic()<deadline:
  assert process.poll() is None,('child exited before read',process.returncode)
  fields=Path('/proc')/str(process.pid)/'syscall'
  state=fields.read_text().split()
  if len(state)>1 and state[0]=='0' and int(state[1],16)==fd:return
  time.sleep(0.005)
 raise AssertionError('child did not reach the required blocking read')
def expect_line(process,expected):
 with selectors.DefaultSelector() as selector:
  selector.register(process.stdout,selectors.EVENT_READ)
  assert selector.select(5),'timed out awaiting signal test marker'
  actual=process.stdout.readline()
  assert actual==expected,(actual,expected)
def exercise(executable):
 r=checked([executable]);assert r.stdout==b'signal contracts passed\n' and not r.stderr
 r=run([executable,'default']);assert r.returncode==-signal.SIGUSR1 and not r.stdout and not r.stderr
 reader,writer=os.pipe()
 process=None
 try:
  process=subprocess.Popen([str(executable),'restart',str(reader)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,pass_fds=(reader,),preexec_fn=no_core,bufsize=0)
  expect_line(process,b'ready\n');waiting_read(process,reader)
  os.kill(process.pid,signal.SIGUSR1)
  expect_line(process,b'handled\n');waiting_read(process,reader)
  os.write(writer,b'R');os.close(writer);writer=-1
  stdout,stderr=process.communicate(timeout=5)
  assert process.returncode==0 and stdout==b'restart passed\n' and not stderr,(process.returncode,stdout,stderr)
 finally:
  os.close(reader)
  if writer>=0:os.close(writer)
  if process is not None and process.poll() is None:
   process.kill();process.communicate(timeout=5)
 return {'persistent_handler':True,'old_handler_values':True,'ignore_default_and_invalid_signals':True,'kernel_action_layout_flags_restorer_mask':True,'blocked_delivery_and_mask_restoration':True,'same_signal_deferred_until_return':True,'observed_interrupted_blocking_read_restart':True}
identity=checked(CC+['--print-source-hash']).stdout.decode().strip()
production=OUT/'forth-signal'
checked(CC+['-o',production,SOURCE])
report={'compiler_source_identity':identity,'production':exercise(production),'production_executable_sha256':hashlib.sha256(production.read_bytes()).hexdigest(),'host_oracles':[]}
host=shutil.which('gcc')
if host:
 for optimization in ['-O0','-O2']:
  oracle=OUT/('host-signal'+optimization[1:])
  checked([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-D_GNU_SOURCE','-DSIGNAL_HOST_ORACLE',optimization,SOURCE,'-o',oracle])
  report['host_oracles'].append({'optimization':optimization,'checks':exercise(oracle)})
assert identity==checked(CC+['--print-source-hash']).stdout.decode().strip(),'compiler changed during check'
report['inputs']={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ['122-cc-sysv-runtime.fth','tools/gcc-direct-cc.py','runtime/gcc-seed/signal.c','runtime/gcc-seed/include/signal.h','tests/gcc/signal-check.c','tests/gcc/signal-check.py']}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: Forth signal/restorer, real delivery/return/masks/default/ignore/errors and blocking-read restart; host C90 O0/O2:',bool(host))
print('Report:',OUT/'report.json')
