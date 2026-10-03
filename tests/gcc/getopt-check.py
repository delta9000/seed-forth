#!/usr/bin/env python3
"""Original oyacc short-option surface, independent cases and host oracle."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='getopt-check-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
SOURCE=ROOT/'tests/gcc/getopt-check.c'
cases=[
 ([], 'end 1\n'),
 (['-dv','file'], '100 1 (null)\n118 2 (null)\nend 2 file\n'),
 (['-bprefix','-oparser.c','-px','file'], '98 2 prefix\n111 3 parser.c\n112 4 x\nend 4 file\n'),
 (['-d','-b','prefix','--','-file'], '100 2 (null)\n98 4 prefix\nend 5 -file\n'),
 (['-d','operand','-v'], '100 2 (null)\nend 2 operand -v\n'),
 (['-o','-d'], '111 3 -d\nend 3\n'),
 (['-xv'], '63 1 (null)\noptopt 120\n118 2 (null)\nend 2\n'),
 (['-o'], '63 2 (null)\noptopt 111\nend 2\n'),
 (['colon','-o'], '58 2 (null)\noptopt 111\nend 2\n'),
 (['-'], 'end 1 -\n'),
 (['--'], 'end 2\n'),
 (['--','-d'], 'end 2 -d\n'),
 (['-d','--','-v'], '100 2 (null)\nend 3 -v\n'),
 (['-b',''], '98 3 \nend 3\n'),
 (['-dlrtv'], '100 1 (null)\n108 1 (null)\n114 1 (null)\n116 1 (null)\n118 2 (null)\nend 2\n'),
]
def run(args):
 env=os.environ.copy();env['POSIXLY_CORRECT']='1';env['LC_ALL']='C'
 r=subprocess.run([str(x) for x in args],capture_output=True,timeout=120,env=env)
 assert r.returncode==0,(args,r.returncode,r.stdout,r.stderr)
 return r
def exercise(executable):
 outputs=[]
 for args,expected in cases:
  r=run([executable]+args)
  assert r.stdout.decode()==expected*2 and not r.stderr,(args,r.stdout,r.stderr,expected)
  outputs.append(hashlib.sha256(r.stdout).hexdigest())
 for args,expected in [(['diagnostic','-x'],"oyacc-test: invalid option -- 'x'\n"),(['diagnostic','-o'],"oyacc-test: option requires an argument -- 'o'\n")]:
  r=run([executable]+args);assert r.stderr.decode()==expected*2,(args,r.stderr)
 # Independent argv permutations use the original option vocabulary and
 # compare observed output only; no generated option table is a build input.
 for flags in ['d','lr','tv','dltvr','xv']:
  for arg in ['value','-d','']:
   for grouped in [False,True]:
    args=['-'+flags+'o'+arg] if grouped else ['-'+flags,'-o',arg]
    r=run([executable]+args+['operand','-v']);assert not r.stderr
    outputs.append(hashlib.sha256(r.stdout).hexdigest())
 return outputs
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
production=OUT/'forth-getopt';run(CC+['-o',production,SOURCE])
outputs=exercise(production)
report={'compiler_source_identity':identity,'production_case_runs':len(outputs)+2,'parse_restarts_per_case':2,'production_passed':True,'host_oracles':[],'outputs_sha256':outputs,'production_executable_sha256':hashlib.sha256(production.read_bytes()).hexdigest()}
host=shutil.which('gcc')
if host:
 for optimization in ['-O0','-O2']:
  executable=OUT/('host-getopt'+optimization[1:])
  run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-D_POSIX_C_SOURCE=200809L',optimization,SOURCE,'-o',executable])
  assert exercise(executable)==outputs,optimization+' host difference'
  report['host_oracles'].append({'optimization':optimization,'matches_forth':True})
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip(),'compiler changed during check'
report['inputs']={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ['runtime/gcc-seed/getopt.c','runtime/gcc-seed/include/unistd.h','tests/gcc/getopt-check.c','tests/gcc/getopt-check.py']}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: getopt',len(outputs)+2,'argument cases, each parsed twice; host C90 O0/O2:',bool(host))
print('Report:',OUT/'report.json')
