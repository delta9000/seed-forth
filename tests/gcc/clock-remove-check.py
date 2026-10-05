#!/usr/bin/env python3
"""Forth production, syscall fault boundaries, and independent host filesystem oracle."""
from pathlib import Path
import json,os,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='clock-remove-',dir=ROOT/'build-out'))
commands=[]
def run(args,cwd=None):
    p=subprocess.run(list(map(str,args)),cwd=cwd,capture_output=True,timeout=180)
    commands.append({'arguments':list(map(str,args)),'returncode':p.returncode,'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace')})
    (OUT/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    assert p.returncode==0 and not p.stderr,(args,p.returncode,p.stderr)
    return p.stdout
cc=[sys.executable,ROOT/'tools/gcc-direct-cc.py']
for name in ('clock-remove-check','clock-remove-fault-check'):
    run(cc+[ROOT/'tests/gcc'/f'{name}.c','-o',OUT/name])
assert run([OUT/'clock-remove-fault-check'])==b'clock/remove fault checks passed\n'
assert run([OUT/'clock-remove-check','clock']).startswith(b'clock ')

def filesystem(binary,label,strict_errno):
    d=OUT/label;d.mkdir()
    def remove(path,value,error=None):
        got=list(map(int,run([binary,'remove',str(path)],cwd=d).split()))
        assert got[0]==value,(path,got,value)
        if value<0:assert got[1]==error,(path,got,error)
        elif strict_errno:assert got[1]==71,(path,got)
    p=d/'file';p.write_bytes(b'open file content')
    with p.open('rb') as held:
        remove(p,0);assert not p.exists();assert held.read()==b'open file content'
    target=d/'target';target.write_text('preserved');link=d/'hard';os.link(target,link)
    remove(link,0);assert target.read_text()=='preserved'
    for name,target_path in [('file-link',target),('dangling',d/'absent')]:
        p=d/name;p.symlink_to(target_path);remove(p,0);assert not p.is_symlink()
    empty=d/'empty';empty.mkdir();p=d/'dir-link';p.symlink_to(empty,target_is_directory=True)
    remove(p,0);assert empty.is_dir();remove(empty,0);assert not empty.exists()
    nonempty=d/'nonempty';nonempty.mkdir();(nonempty/'child').write_text('keep')
    remove(nonempty,-1,39);assert (nonempty/'child').read_text()=='keep'
    remove(d/'absent',-1,2);remove('',-1,2);remove(target/'child',-1,20)
    p=d/'fifo';os.mkfifo(p);remove(p,0);assert not p.exists()
    p=d/('n'*255);p.touch();remove(p.name,0);assert not p.exists()
    p=d/'trailing';p.mkdir();remove(str(p)+'/',0);assert not p.exists()
    permission='not tested as root'
    if os.geteuid()!=0:
        p=d/'protected';p.mkdir();(p/'child').write_text('keep');p.chmod(0o500)
        try:remove(p/'child',-1,13);assert (p/'child').exists();permission='EACCES checked'
        finally:p.chmod(0o700)
    return permission
permission=filesystem(OUT/'clock-remove-check','forth-files',True)
for opt in ('-O0','-O2'):
    executable=OUT/('host'+opt)
    run(['gcc','-D_GNU_SOURCE','-DHOST_ORACLE','-std=c90','-pedantic','-fno-builtin',opt,
         ROOT/'tests/gcc/clock-remove-check.c','-o',executable])
    assert run([executable,'clock']).startswith(b'clock ')
    filesystem(executable,'host-files'+opt,False)
    fault=OUT/('host-fault'+opt)
    run(['gcc','-std=c90','-pedantic','-fno-builtin',opt,'-I'+str(ROOT/'runtime/gcc-seed/include'),
         ROOT/'tests/gcc/clock-remove-fault-check.c','-o',fault])
    assert run([fault])==b'clock/remove fault checks passed\n'
report={'production':'Forth compiler/linker/runtime only','oracle':'host GCC O0/O2 separate',
        'clock':'process CPU syscall bracket, CPU busy loop and sleep exclusion',
        'faults':'all4095 negative kernel codes, LONG_MAX and submicrosecond boundaries, malformed timespec, remove EISDIR fallback',
        'remove':'files, openfiles, hardlinks, symlinks, danglinglinks, empty/nonemptydirectories, FIFO,255byte names, relativepaths,trailing slash',
        'permission':permission,'clock_t_bytes':8,'CLOCKS_PER_SEC':1000000,'host_success_errno':'unspecified; production separately preserves errno'}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS clock/remove Forth production, exact/fault boundaries and GCC O0/O2 oracles')
print(OUT/'report.json')
