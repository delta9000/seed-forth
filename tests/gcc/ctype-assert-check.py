#!/usr/bin/env python3
"""Forth-only checks for the measured oyacc C-locale and assertion surface."""
from pathlib import Path
import hashlib,json,resource,shutil,signal,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='ctype-assert-check-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
report={'compiler_source_identity':subprocess.check_output(CC+['--print-source-hash'],timeout=120).decode().strip(),'checks':[]}
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(args):
 def limit_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
 return subprocess.run([str(x) for x in args],capture_output=True,preexec_fn=limit_core,timeout=120)
for stem in ['ctype-check','assert-check','assert-helper-check']:
 source=ROOT/'tests/gcc'/(stem+'.c');exe=OUT/stem
 result=run(CC+['-o',exe,source]);(OUT/(stem+'.compile.stderr')).write_bytes(result.stderr)
 assert result.returncode==0,(stem,result.returncode,result.stderr.decode())
 report['checks'].append({'fixture':stem,'source_sha256':digest(source),'executable_sha256':digest(exe)})
ctype=run([OUT/'ctype-check']);assert ctype.returncode==0,ctype.stderr
expected=[]
for value in range(-1,256):
 alpha=value in range(65,91) or value in range(97,123)
 digit=value in range(48,58)
 values=[value,int(alpha),int(alpha or digit),int(digit),int(value in range(32,127)),int(value in [9,10,11,12,13,32]),int(value in range(65,91)),value+32 if value in range(65,91) else value]
 expected.append(' '.join(map(str,values)))
assert ctype.stdout.decode()=='\n'.join(expected)+'\n'
assert not ctype.stderr
(OUT/'ctype-actual.txt').write_bytes(ctype.stdout)
report['ctype_argument_values_checked']=257
success=run([OUT/'assert-check']);assert success.returncode==0 and not success.stdout and not success.stderr
failure=run([OUT/'assert-check','fail']);assert failure.returncode==-signal.SIGABRT,(failure.returncode,failure.stderr)
source=(ROOT/'tests/gcc/assert-check.c').read_text();line=next(i for i,x in enumerate(source.splitlines(),1) if 'assert(argv == 0)' in x)
expected=f"{ROOT/'tests/gcc/assert-check.c'}:{line}: assertion `argv == 0' failed\n".encode()
assert failure.stderr==expected,(failure.stderr,expected)
assert not failure.stdout
(OUT/'assert-failure.stderr').write_bytes(failure.stderr)
helper=run([OUT/'assert-helper-check']);assert helper.returncode==-signal.SIGABRT
assert helper.stderr==b"owned-fixture.c:73: test_function: assertion `helper test' failed\n"
assert not helper.stdout
report['assert_checks']=['true expression evaluated once','pointer condition','NDEBUG expression not evaluated','NDEBUG need not resolve expression identifiers','reinclusion after NDEBUG change','failure source file and line','SIGABRT through real runtime','explicit function-name helper diagnostic']
report['runtime_inputs']={str(p.relative_to(ROOT)):digest(p) for p in sorted((ROOT/'runtime/gcc-seed').rglob('*')) if p.is_file()}
assert report['compiler_source_identity']==subprocess.check_output(CC+['--print-source-hash'],timeout=120).decode().strip(),'compiler changed during checks'
# This independently built same fixture uses host headers and libc only as an
# oracle; neither host executable is a production bootstrap input.
host=shutil.which('gcc')
report['host_ctype_oracle']={'available':bool(host),'runs':[]}
if host:
 for optimization in ['-O0','-O2']:
  executable=OUT/('host-ctype'+optimization[1:])
  built=run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror',optimization,ROOT/'tests/gcc/ctype-check.c','-o',executable])
  assert built.returncode==0,built.stderr
  oracle=run([executable]);assert oracle.returncode==0 and not oracle.stderr
  assert oracle.stdout==ctype.stdout,(optimization,'host C-locale ctype output differs')
  report['host_ctype_oracle']['runs'].append({'optimization':optimization,'matches_forth':True,'executable_sha256':digest(executable)})
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: 257 ctype inputs, assertion/NDEBUG reinclusion, exact diagnostics and real SIGABRT')
print('Host ctype oracle:', 'C90 O0 and O2 match' if host else 'unavailable; production checks passed independently')
print('Report:',OUT/'report.json')
