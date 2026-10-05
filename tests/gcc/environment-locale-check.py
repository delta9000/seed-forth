#!/usr/bin/env python3
"""Actual startup environment and explicit C/POSIX locale selection."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2];(ROOT/'build-out').mkdir(exist_ok=True);OUT=Path(tempfile.mkdtemp(prefix='environment-locale-',dir=ROOT/'build-out'));CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(command,**kwargs):
 r=subprocess.run(list(map(str,command)),capture_output=True,timeout=120,**kwargs);assert r.returncode==0,(command,r.returncode,r.stdout,r.stderr);return r
cases=[({},1,1),({'LANG':'C'},1,1),({'LANG':'POSIX'},1,1),({'LANG':'seed_no_such_locale_20261003'},0,0),({'LANG':'seed_no_such_locale_20261003','LC_CTYPE':'C'},1,0),({'LC_ALL':'C','LANG':'seed_no_such_locale_20261003','LC_CTYPE':'seed_no_such_locale_20261003'},1,1),({'LC_ALL':'POSIX','LC_CTYPE':'seed_no_such_locale_20261003'},1,1),({'LC_ALL':'seed_no_such_locale_20261003','LANG':'C','LC_CTYPE':'C'},0,0),({'LC_ALL':'','LC_CTYPE':'','LANG':'C'},1,1),({'LC_CTYPE':'POSIX','LANG':'C'},1,1),({'LC_NUMERIC':'seed_no_such_locale_20261003','LANG':'C'},1,0),({'LC_ALL':'C','LC_NUMERIC':'seed_no_such_locale_20261003'},1,1)]
def exercise(executable):
 for environment,ctype,all_categories in cases:
  env=dict(environment,SEED_ENV_TEST='runtime marker',SEED_ENV_TESTER='other')
  for category,expected in [('ctype',ctype),('all',all_categories)]:
   r=run([executable,category],env=env);assert r.stdout==f'{expected} C\n'.encode() and not r.stderr,(environment,category,r.stdout,r.stderr)
identity=run(CC+['--print-source-hash']).stdout.decode().strip();exe=OUT/'locale';run(CC+['-o',exe,ROOT/'tests/gcc/environment-locale-check.c']);exercise(exe)
r=run([exe,'ctype'],env={'LC_ALL':'C.UTF-8','SEED_ENV_TEST':'runtime marker'});assert r.stdout==b'0 C\n' and not r.stderr
report={'compiler_source_identity':identity,'environment_cases':len(cases),'categories_per_case':2,'actual_environment_pointer_and_getenv':True,'unsupported_UTF8_request_rejected':True,'host_oracles':[]};host=shutil.which('gcc')
if host:
 for level in ['-O0','-O2']:
  target=OUT/('host'+level[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-D_GNU_SOURCE',level,ROOT/'tests/gcc/environment-locale-check.c','-o',target]);exercise(target);report['host_oracles'].append(level)
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip(),'compiler changed during test'
names=['122-cc-sysv-runtime.fth','runtime/gcc-seed/startup.c','runtime/gcc-seed/environment.c','runtime/gcc-seed/locale.c','runtime/gcc-seed/include/locale.h','runtime/gcc-seed/include/unistd.h','runtime/gcc-seed/include/stdlib.h','tests/gcc/environment-locale-check.c','tests/gcc/environment-locale-check.py'];report['source_sha256']={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names};report['artifact_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.is_file()};(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: genuine environment/getenv and24locale-precedence cases; hostO0/O2:',bool(host));print(OUT/'report.json')
