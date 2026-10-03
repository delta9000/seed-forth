#!/usr/bin/env python3
"""Forth descriptor/tempfile contracts, scripted faults, separate libc oracle."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='descriptor-check-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(args,status=0,**kwargs):
 r=subprocess.run([str(x) for x in args],capture_output=True,timeout=120,**kwargs)
 assert r.returncode==status,(args,r.returncode,r.stdout,r.stderr)
 return r
def produce(name,source,objects=()):
 exe=OUT/name;run(CC+['-o',exe,source]+list(objects));return exe
def exercise(executable,host=False):
 directory=Path(tempfile.mkdtemp(prefix='files-',dir=OUT))
 r=run([executable,directory],preexec_fn=lambda:os.umask(0o077))
 assert r.stdout==b'descriptor contracts passed\n' and not r.stderr
 assert not list(directory.iterdir()),'temporary files leaked'
 r=run([executable,directory,'exit'],status=3);assert not r.stdout and not r.stderr
 content=(directory/'before-exit').read_bytes()
 if not host:assert content==b'before _exit\n'
 return {'normal_cleanup_passed':True,'exit_status':3,'exit_file_hex':content.hex()}
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
production=produce('descriptor',ROOT/'tests/gcc/descriptor-check.c')
report={'compiler_source_identity':identity,'production':exercise(production),'host_oracles':[]}
obj=OUT/'tested-mkstemp.o';run(CC+['-Dmkstemp=tested_mkstemp','-D__seed_syscall6=tested_temp_syscall','-c','-o',obj,ROOT/'runtime/gcc-seed/mkstemp.c'])
exe=produce('mkstemp-faults',ROOT/'tests/gcc/mkstemp-faults.c',[obj]);r=run([exe]);assert r.stdout==b'tempfile fault contracts passed\n' and not r.stderr
names='__seed_stdin __seed_stdout __seed_stderr fopen fdopen fclose fflush ferror feof clearerr fwrite fread fputc putc putchar fputs puts fgetc getc getchar ungetc ftell vfprintf fprintf vprintf printf vsnprintf snprintf vsprintf sprintf perror'.split()
obj=OUT/'tested-stdio.o';run(CC+['-D'+n+'=tested_'+n for n in names]+['-Dmalloc=tested_stream_malloc','-Dfree=tested_stream_free','-D__seed_syscall6=tested_stream_syscall','-c','-o',obj,ROOT/'runtime/gcc-seed/stdio.c'])
exe=produce('fdopen-faults',ROOT/'tests/gcc/fdopen-faults.c',[obj]);r=run([exe]);assert r.stdout==b'fdopen fault contracts passed\n' and not r.stderr
report['scripted_faults']=['getrandom EINTR/partial/zero/error and exact partial-read pointer progression','exclusive open EINTR/collision/error/exhaustion','invalid template unchanged','F_GETFL/F_SETFL EINTR/error','mode/access/O_PATH validation','allocation failure preserves descriptor','failure frees only stream memory','successful close owns descriptor once']
host=shutil.which('gcc')
if host:
 for optimization in ['-O0','-O2']:
  exe=OUT/('host-descriptor'+optimization[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-D_GNU_SOURCE','-DDESCRIPTOR_HOST_ORACLE',optimization,ROOT/'tests/gcc/descriptor-check.c','-o',exe]);report['host_oracles'].append({'optimization':optimization,'checks':exercise(exe,host=True)})
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip(),'compiler changed during test'
names=['runtime/gcc-seed/stdio.c','runtime/gcc-seed/mkstemp.c','runtime/gcc-seed/posix.c','runtime/gcc-seed/include/stdio.h','runtime/gcc-seed/include/stdlib.h','runtime/gcc-seed/include/unistd.h','runtime/gcc-seed/include/fcntl.h','runtime/gcc-seed/include/paths.h','tests/gcc/descriptor-check.c','tests/gcc/mkstemp-faults.c','tests/gcc/fdopen-faults.c','tests/gcc/descriptor-check.py']
report['source_sha256']={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names};report['artifact_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.is_file()}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: descriptors/tempfiles/cleanup/_exit, isolated faults, host O0/O2:',bool(host));print(OUT/'report.json')
