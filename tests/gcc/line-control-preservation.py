#!/usr/bin/env python3
"""Compare old/new preprocessor bytes and legacy/native ELF emission."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--baseline',type=Path,required=True);args=ap.parse_args()
    baseline=args.baseline.read_bytes();current=(ROOT/'040-cc-prep.fth').read_bytes()
    assert hashlib.sha256(baseline).hexdigest()=='5708cccd9f44de31878d31b80b48247f573a7559f996aa06073c42f4444e6426'
    paths=[ROOT/'010-lib.fth']+sorted(p for p in ROOT.glob('[0-9][0-9][0-9]-cc-*.fth') if p.name not in ('120-cc-main.fth','140-cc-link.fth'))
    vocab=[b'\n'.join((baseline if old and p.name=='040-cc-prep.fth' else p.read_bytes()) for p in paths) for old in (True,False)]
    work=Path(tempfile.mkdtemp(prefix='line-preservation-',dir=ROOT/'build-out'));records=[]
    def compare(name,source,setup=b'',compile_word=None):
        suffix=b'cc-load-stdin cc-preprocess '
        if compile_word:
            suffix+=b'cc-out-init cc-globals-init cc-emit-elf-header '+compile_word+b' cc-finalize-globals cc-finalize-elf [lit] 1 cc-out-buf cc-out-pos @ write drop bye'
        else:suffix+=b'[lit] 1 cc-src-buf cc-src-len @ write drop bye'
        script=setup+b'\n: preserve-check '+suffix+b' ;\npreserve-check\n';answers=[]
        for v in vocab:
            p=subprocess.run([ROOT/'seed-forth'],input=v+b'\n'+script+source,capture_output=True,cwd=ROOT,timeout=90)
            assert p.returncode==0 and not p.stderr,(name,p.returncode,p.stdout[:150],p.stderr);answers.append(p.stdout)
        assert answers[0]==answers[1],name
        records.append({'case':name,'bytes':len(answers[0]),'sha256':hashlib.sha256(answers[0]).hexdigest()})
    for name in ['P1-conditionals.c','P2-fn-macros.c','P3-casts.c','P8-libc-shims.c']:
        source=(ROOT/'tests/cc'/name).read_bytes();compare('legacy-prep-'+name,source);compare('legacy-elf-'+name,source,compile_word=b'cc-parse-program')
    compare('direct-TinyCC-profile-prep-smoke',(ROOT/'tests/tcc/prep-smoke.c').read_bytes(),b'true cc-prep-direct !')
    compare('legacy-line-policy',b'#line 5 "virtual.c"\n__LINE__ __FILE__\n')
    compare('direct-TinyCC-line-policy',b'#line 5 "virtual.c"\n__LINE__ __FILE__\n',b'true cc-prep-direct !')
    for name in ['basics','layout','stack-call','literals','many-args','switch-goto']:
        compare('native-elf-'+name,(ROOT/f'tests/tcc/native-{name}.c').read_bytes(),b'true cc-target-lp64 !\ntrue cc-prep-direct !\n[lit] 8388608 cc-arena-map\n',b'cc-native-program')
    report={'status':'PASS','baseline_040_sha256':hashlib.sha256(baseline).hexdigest(),'current_040_sha256':hashlib.sha256(current).hexdigest(),'cases':records,'scope':'Raw output byte identity on existing legacy/native and direct-TinyCC-profile fixtures, not complete TinyCC rebuild'}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: prior-profile preprocessing and ELF bytes preserved');print(work/'report.json')
if __name__=='__main__':main()
