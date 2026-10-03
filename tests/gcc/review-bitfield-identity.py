#!/usr/bin/env python3
"""Compare the frozen pre-bitfield baseline with the reviewed bitfield compiler.

Only reads Git; historical source bytes are loaded into temporary compiler input,
not checked out or written into the working tree. The bitfield owner identified
these five replacement layers and the omitted 129 as the complete delta.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
PRE_BITFIELD_COMMIT='f6777bf6b657cbd10601f52d482891959da3a05f'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler-root',type=Path,default=ROOT/'build-out/bitfield-work')
    parser.add_argument('--scalar-checkpoint',type=Path,default=ROOT/'build-out/sysv-binary64-checkpoint-20261003T1713')
    parser.add_argument('--report',type=Path,default=ROOT/'tests/gcc/review-bitfield-identity-results.json')
    args=parser.parse_args()
    compiler=args.compiler_root.resolve()
    paths=[compiler/'010-lib.fth',*sorted(p for p in compiler.glob('[0-9][0-9][0-9]-cc-*.fth') if p.name!='120-cc-main.fth')]
    current={p.name:p.read_bytes() for p in paths}
    before=dict(current)
    del before['129-cc-bitfield.fth']
    for name in ('100-cc-expr.fth','118-cc-native-init.fth','123-cc-object-program.fth'):
        before[name]=(args.scalar_checkpoint/name).read_bytes()
    for name in ('060-cc-types.fth','115-cc-native.fth'):
        before[name]=subprocess.run(['git','show',PRE_BITFIELD_COMMIT+':'+name],cwd=ROOT,capture_output=True,check=True).stdout
    fixtures=[('default','tests/cc/C-struct-global.c',7),('native','tests/tcc/native-layout.c',0),('native','tests/cc/T2-native-expressions.c',0),('native','tests/cc/T4-native-expression-edges.c',0)]
    results=[]
    with tempfile.TemporaryDirectory(prefix='review-bitfield-identity-') as td:
        work=Path(td)
        for index,(mode,filename,expected) in enumerate(fixtures):
            source=(ROOT/filename).read_bytes()
            emitted=[]
            for label,layers in [('baseline',before),('bitfields',current)]:
                output=work/f'{index}-{label}'
                driver=('true cc-target-lp64 ! true cc-prep-direct !\n[lit] 8388608 cc-arena-map\n' if mode=='native' else '')
                driver+=f'create review-output s, {output} [lit] 0 c,\n'
                driver+=': review-main cc-load-stdin cc-preprocess cc-out-init cc-globals-init cc-emit-elf-header '
                driver+=('cc-native-program' if mode=='native' else 'cc-parse-program')
                driver+=' cc-finalize-globals cc-finalize-elf review-output cc-write-output bye ;\nreview-main\n'
                input_bytes=b'\n'.join(layers.values())+b'\n'+driver.encode()+source
                run=subprocess.run([compiler/'seed-forth'],input=input_bytes,capture_output=True,timeout=120)
                assert run.returncode==0 and not run.stdout and not run.stderr,(filename,label,run.returncode,run.stdout,run.stderr)
                output.chmod(0o700)
                result=subprocess.run([output],capture_output=True,timeout=10)
                assert result.returncode==expected,(filename,label,result.returncode)
                emitted.append(output.read_bytes())
            assert emitted[0]==emitted[1],filename+' emitted bytes changed'
            results.append({'mode':mode,'fixture':filename,'fixture_sha256':digest(source),'executable_sha256':digest(emitted[0]),'bytes':len(emitted[0]),'exit':expected})
            print('PASS:',mode,filename,'byte-identical',len(emitted[0]),'bytes')
    assert current=={p.name:p.read_bytes() for p in paths},'Reviewed compiler changed'
    report={'review_script_sha256':digest(Path(__file__).read_bytes()),'baseline_git_commit':PRE_BITFIELD_COMMIT,'baseline_compiler_sha256':{n:digest(d) for n,d in before.items()},'reviewed_compiler_sha256':{n:digest(d) for n,d in current.items()},'fixtures':results}
    args.report.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(args.report)


if __name__=='__main__':
    main()
