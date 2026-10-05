#!/usr/bin/env python3
"""One-syscall POSIX write: real partial pipe transfer and error boundaries."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2];(ROOT/'build-out').mkdir(exist_ok=True);OUT=Path(tempfile.mkdtemp(prefix='write-check-',dir=ROOT/'build-out'));CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(args):
 r=subprocess.run(list(map(str,args)),capture_output=True,timeout=120);assert r.returncode==0,(args,r.returncode,r.stdout,r.stderr);return r
identity=run(CC+['--print-source-hash']).stdout.decode().strip();exe=OUT/'write';run(CC+['-o',exe,ROOT/'tests/gcc/write-check.c']);r=run([exe]);assert r.stdout==b'write contracts passed\n' and not r.stderr
obj=OUT/'write-faults.o';run(CC+['-Dwrite=tested_write','-D__seed_syscall6=tested_write_syscall','-c','-o',obj,ROOT/'runtime/gcc-seed/write.c']);faults=OUT/'faults';run(CC+['-o',faults,ROOT/'tests/gcc/write-faults.c',obj]);r=run([faults]);assert r.stdout==b'write fault contracts passed\n' and not r.stderr
report={'compiler_source_identity':identity,'production':'zero count, invalid descriptor, real EAGAIN and4096-byte partial write from8192 request','faults':'one-call argument forwarding, partial result, EINTR/no retry, ENOSPC, zero count, errno preservation','host_oracles':[]};host=shutil.which('gcc')
if host:
 for level in ['-O0','-O2']:
  oracle=OUT/('oracle'+level[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-D_GNU_SOURCE','-DWRITE_HOST_ORACLE',level,ROOT/'tests/gcc/write-check.c','-o',oracle]);r=run([oracle]);assert r.stdout==b'write contracts passed\n' and not r.stderr;report['host_oracles'].append(level)
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip(),'compiler changed during test'
report['source_sha256']={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in ['runtime/gcc-seed/write.c','runtime/gcc-seed/include/unistd.h','tests/gcc/write-check.c','tests/gcc/write-faults.c','tests/gcc/write-check.py']};report['artifact_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.is_file()};(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: real and fault write contracts; hostO0/O2:',bool(host));print(OUT/'report.json')
