#!/usr/bin/env python3
"""Real terminal, pipe, file and invalid-descriptor checks plus fault injection."""
from pathlib import Path
import hashlib,importlib.util,json,os,pty,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2];(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='isatty-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(args,**kw):
    r=subprocess.run(list(map(str,args)),capture_output=True,timeout=120,**kw)
    assert r.returncode==0,(args,r.returncode,r.stdout,r.stderr)
    return r
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
source=ROOT/'tests/gcc/isatty-check.c';production=OUT/'production';run(CC+['-o',production,source])
master,slave=pty.openpty();read_pipe,write_pipe=os.pipe();file_fd=os.open(OUT/'ordinary',os.O_CREAT|os.O_RDWR,0o600)
fds=[master,slave,read_pipe,write_pipe,file_fd]
def check(executable):
    outputs={}
    for label,fd,expected in [('pty-master',master,b'1 33\n0 9\n'),('pty-slave',slave,b'1 33\n0 9\n'),('pipe-read',read_pipe,b'0 25\n0 9\n'),('pipe-write',write_pipe,b'0 25\n0 9\n'),('file',file_fd,b'0 25\n0 9\n')]:
        r=run([executable,str(fd)],pass_fds=(fd,));assert r.stdout==expected and not r.stderr,(label,r.stdout,r.stderr);outputs[label]=r.stdout.decode()
    return outputs
report={'compiler_source_identity':identity,'production':check(production),'host_oracles':{}}
try:
    host=shutil.which('gcc')
    if host:
        for level in ['-O0','-O2']:
            executable=OUT/('host'+level[1:]);run([host,'-std=c90','-pedantic','-Wall','-Wextra','-Werror','-D_POSIX_C_SOURCE=200809L',level,source,'-o',executable]);report['host_oracles'][level]=check(executable)
finally:
    for fd in fds:os.close(fd)
spec=importlib.util.spec_from_file_location('stdio_check',ROOT/'tests/gcc/stdio-check.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
objects=[]
for source in [ROOT/'runtime/gcc-seed/isatty.c',ROOT/'tests/gcc/isatty-faults.c']:
    obj=OUT/(source.stem+'.o');run([ROOT/'tests/gcc/sysv-object-compile.sh',source,obj,ROOT/'runtime/gcc-seed/include']);objects.append(obj)
driver=''
for name,builder in [('errno','cc-sysrt-errno-object'),('start','cc-sysrt-start-object')]:
    obj=OUT/(name+'.o');driver+=module.path_word(name+'-output',obj)+builder+' '+name+'-output cc-obj-write\n';objects.append(obj)
module.forth(module.BASE+['081-cc-object.fth','122-cc-sysv-runtime.fth'],driver+'bye\n');module.link(objects,OUT/'faults');run([OUT/'faults']);report['syscall_faults']='pass'
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip()
names=['runtime/gcc-seed/isatty.c','runtime/gcc-seed/include/unistd.h','runtime/gcc-seed/include/errno.h','tests/gcc/isatty-check.c','tests/gcc/isatty-check.py','tests/gcc/isatty-faults.c'];report['source_sha256']={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: real PTYs, pipe/file/invalid descriptors, syscall contract; hostO0/O2:',bool(host));print(OUT/'report.json')
