#!/usr/bin/env python3
"""Real Forth-built SIGABRT behavior; separate host signal-handler ABI oracles."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import resource
import shutil
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def no_core():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run(command, status=0, stdout=b'', **kwargs):
    result = subprocess.run(command, capture_output=True, timeout=60,
                            preexec_fn=no_core, **kwargs)
    if (result.returncode, result.stdout, result.stderr) != (status, stdout, b''):
        raise AssertionError((command, result.returncode, result.stdout, result.stderr))
    return result


def word(name, path):
    return 'create '+name+'\n'+''.join('[lit] '+str(b)+' c,\n' for b in os.fsencode(path)+b'\0')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler-root',type=Path,default=ROOT)
    core=parser.parse_args().compiler_root.resolve()
    (ROOT/'build-out').mkdir(exist_ok=True)
    work=Path(tempfile.mkdtemp(prefix='abort-production-',dir=ROOT/'build-out'))
    frozen=work/'source'
    paths=[p for p in core.glob('[0-9][0-9][0-9]-cc-*.fth')]
    paths += [core/'010-lib.fth',core/'seed-forth',core/'000-seed.hex0',core/'tools/gcc-direct-cc.py']
    records={}
    for p in paths:
        name=str(p.relative_to(core)); data=p.read_bytes()
        dest=frozen/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data);dest.chmod(p.stat().st_mode&0o777)
        records[name]=hashlib.sha256(data).hexdigest()
    for p in (ROOT/'runtime/gcc-seed').rglob('*'):
        if p.is_file() and p.suffix in ('.c','.h'):
            name=str(p.relative_to(ROOT));data=p.read_bytes();dest=frozen/name
            dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data);dest.chmod(p.stat().st_mode&0o777)
            records[name]=hashlib.sha256(data).hexdigest()
    tests={}
    for name in ('abort-production.c','abort-oracle.c','abort-faults.c'):
        p=ROOT/'tests/gcc'/name;dest=work/name;shutil.copy2(p,dest);tests[name]=hashlib.sha256(dest.read_bytes()).hexdigest()
    def forth(modules,script):
        data=b'\n'.join((frozen/name).read_bytes() for name in modules)+b'\n'+script.encode()
        run([frozen/'seed-forth'],input=data)
    driver=frozen/'tools/gcc-direct-cc.py'
    process=work/'process.o';client=work/'client.o';oracle_process=work/'oracle-process.o'
    run([driver,'-c',frozen/'runtime/gcc-seed/process.c','-o',process])
    run([driver,'-c',work/'abort-production.c','-o',client])
    run([driver,'-c','-Dabort=seed_abort','-Dexit=seed_exit',frozen/'runtime/gcc-seed/process.c','-o',oracle_process])
    abi=['010-lib.fth','020-cc-arena.fth','030-cc-io.fth','081-cc-object.fth','122-cc-sysv-runtime.fth']
    syscall=work/'syscall.o';start=work/'start.o'
    forth(abi,word('sysout',syscall)+'cc-sysrt-object sysout cc-obj-write\n'+word('startout',start)+'cc-sysrt-start-object startout cc-obj-write bye\n')
    executable=work/'abort'
    script='lnk-init\n'
    for i,p in enumerate([process,client,syscall,start]):script+=word('object'+str(i),p)+'object'+str(i)+' lnk-add-object\n'
    script+='create entry s, _start\nentry [lit] 6 lnk-entry\n'+word('output',executable)+'output lnk-link bye\n'
    forth(['010-lib.fth','020-cc-arena.fth','030-cc-io.fth','140-cc-link.fth'],script)
    for mode in ('default','blocked','ignored'):
        run([executable,mode],status=-signal.SIGABRT,stdout=b'before abort\n')
    print('PASS: Forth-only abort terminates by SIGABRT with default, blocked and ignored disposition')
    for opt in ('-O0','-O2'):
        oracle=work/('oracle'+opt)
        run(['cc','-std=c90',opt,'-fno-pie','-no-pie',work/'abort-oracle.c',oracle_process,syscall,'-o',oracle])
        for mode,status in [('0',-signal.SIGABRT),('1',0),('2',42),('3',-signal.SIGABRT)]:
            run([oracle,mode],status=status,stdout=b'handler\n')
        faults=work/('faults'+opt)
        run(['cc','-std=c90',opt,'-fno-pie','-no-pie',work/'abort-faults.c',oracle_process,'-o',faults])
        run([faults],status=134)
        print('PASS: returning/nonreturning handlers, mask changes and denied-delivery fallback',opt)
    assert all(hashlib.sha256((frozen/name).read_bytes()).hexdigest()==digest for name,digest in records.items())
    report={'status':'PASS','compiler_source_root':str(core),'production':'Forth C objects, syscall/start objects and Forth linker; actual Linux signal termination','oracle':'Host C handlers/syscall double only in separate executables','source_sha256':records,'test_source_sha256':tests,'production_cases':['default SIGABRT','blocked SIGABRT','ignored SIGABRT'],'host_oracle_cases':['handler returns','handler siglongjmp','handler exits42','handler masks/ignores then returns','signal-syscall failure falls back to exit134'],'host_optimizations':['-O0','-O2'],'artifact_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [process,client,oracle_process,syscall,start,executable]}}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(work/'report.json')


if __name__=='__main__':main()
