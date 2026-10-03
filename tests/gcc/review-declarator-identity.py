#!/usr/bin/env python3
"""Isolate the two parser-layer edits and compare legacy output bytes."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
TEST=ROOT/'tests/gcc'
def sha(b):return hashlib.sha256(b).hexdigest()
def main():
    baseline=ROOT/'build-out/declarator-edges-work/baseline'
    names=['010-lib.fth',*[p.name for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth')) if p.name!='120-cc-main.fth']]
    after={n:(ROOT/n).read_bytes() for n in names}
    before=dict(after)
    for n in ('112-cc-stmt.fth','115-cc-native.fth'):before[n]=(baseline/n).read_bytes()
    work=Path(tempfile.mkdtemp(prefix='review-declarator-identity-'))
    source=(work/'review-declarator-identity.c').read_bytes()
    records=[]
    for mode in ('default','native'):
        artifacts=[]
        for label,inputs in [('before',before),('after',after)]:
            out=work/(mode+'-'+label)
            setup='true cc-target-lp64 ! true cc-prep-direct ! [lit] 8388608 cc-arena-map\n' if mode=='native' else ''
            setup+=f'create review-output s, {out} [lit] 0 c,\n'
            setup+=': review-main cc-load-stdin cc-preprocess cc-out-init cc-globals-init cc-emit-elf-header '
            setup+=('cc-native-program' if mode=='native' else 'cc-parse-program')
            setup+=' cc-finalize-globals cc-finalize-elf review-output cc-write-output bye ;\nreview-main\n'
            r=subprocess.run([ROOT/'seed-forth'],input=b'\n'.join(inputs.values())+b'\n'+setup.encode()+source,capture_output=True,timeout=60)
            assert r.returncode==0 and not r.stdout and not r.stderr,(mode,label,r)
            out.chmod(0o700)
            r=subprocess.run([out],capture_output=True,timeout=10)
            assert r.returncode==0,(mode,label,r)
            artifacts.append(out.read_bytes())
        assert artifacts[0]==artifacts[1],mode
        records.append({'mode':mode,'output_sha256':sha(artifacts[0]),'bytes':len(artifacts[0])})
        print('PASS:',mode,'before/after bytes identical')
    assert after=={n:(ROOT/n).read_bytes() for n in names},'compiler changed'
    report={'compiler_sha256':{n:sha(b) for n,b in after.items()},'baseline_edited_layer_sha256':{n:sha(before[n]) for n in ('112-cc-stmt.fth','115-cc-native.fth')},'fixture_sha256':sha(source),'script_sha256':sha(Path(__file__).read_bytes()),'results':records,'work':str(work)}
    (work/'review-declarator-identity-results.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')
if __name__=='__main__':main()
