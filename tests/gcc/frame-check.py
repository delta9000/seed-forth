#!/usr/bin/env python3
"""Verify the private Forth-C frame helper on fixed and temporary call stacks."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]


def run(args,**kwargs):
    result=subprocess.run(args,capture_output=True,timeout=60,**kwargs)
    if (result.returncode,result.stdout,result.stderr)!=(0,b'',b''):
        raise AssertionError((args,result.returncode,result.stdout,result.stderr))


def word(name,path):
    return 'create '+name+'\n'+''.join('[lit] '+str(b)+' c,\n' for b in os.fsencode(path)+b'\0')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler-root',type=Path,default=ROOT)
    core=parser.parse_args().compiler_root.resolve()
    work=Path(tempfile.mkdtemp(prefix='frame-production-',dir=ROOT/'build-out'))
    base=['010-lib.fth','020-cc-arena.fth','030-cc-io.fth']
    paths={name:core/name for name in base+['081-cc-object.fth','140-cc-link.fth']}
    paths['122-cc-sysv-runtime.fth']=ROOT/'122-cc-sysv-runtime.fth'
    data={n:p.read_bytes() for n,p in paths.items()}
    compiler_inputs={p:hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in core.glob('[0-9][0-9][0-9]-cc-*.fth')}
    other_inputs={p:hashlib.sha256(p.read_bytes()).hexdigest() for p in
                  [core/'seed-forth',ROOT/'runtime/gcc-seed/include/seed-frame.h',
                   ROOT/'tests/gcc/frame-production.c',Path(__file__)]}
    def forth(modules,script):
        run([core/'seed-forth'],input=b'\n'.join(data[n] for n in modules)+b'\n'+script.encode())
    frame,start,client=[work/(n+'.o') for n in ('frame','start','client')]
    forth(base+['081-cc-object.fth','122-cc-sysv-runtime.fth'],
          word('frameout',frame)+'cc-sysrt-frame-object frameout cc-obj-write\n'+
          word('startout',start)+'cc-sysrt-start-object startout cc-obj-write bye\n')
    run([core/'tests/gcc/sysv-object-compile.sh',ROOT/'tests/gcc/frame-production.c',client,ROOT/'runtime/gcc-seed/include'])
    exe=work/'frame'
    script='lnk-init\n'
    for i,p in enumerate([start,frame,client]):script+=word('object'+str(i),p)+'object'+str(i)+' lnk-add-object\n'
    script+='create entry s, _start\nentry [lit] 6 lnk-entry\n'+word('output',exe)+'output lnk-link bye\n'
    forth(base+['140-cc-link.fth'],script)
    run([exe])
    assert all(p.read_bytes()==data[n] for n,p in paths.items()),'source changed during test'
    assert all(hashlib.sha256(p.read_bytes()).hexdigest()==h for p,h in
               list(compiler_inputs.items())+list(other_inputs.items())),'test/compiler input changed'
    report={'status':'PASS','proof':'Forth compiler, frame/start objects and Forth linker; no host target code','compiler_root':str(core),'runtime_source_sha256':{n:hashlib.sha256(b).hexdigest() for n,b in data.items()},'compiler_source_sha256':{p.name:h for p,h in compiler_inputs.items()},'other_input_sha256':{str(p):h for p,h in other_inputs.items()},'test_sha256':hashlib.sha256((ROOT/'tests/gcc/frame-production.c').read_bytes()).hexdigest(),'cases':['stable same caller frame across nested argument evaluation','saved parent chain through13 recursive calls','function-pointer callback frames','20 repeated cycles'],'artifact_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [frame,start,client,exe]}}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: private frame helper preserves stable caller identity through temporary stack use, callbacks and recursion')
    print(work/'report.json')


if __name__=='__main__':main()
