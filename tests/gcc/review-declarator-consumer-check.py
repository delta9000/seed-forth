#!/usr/bin/env python3
"""Execute untouched configured upstream sources with Forth and host oracles."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
TEST=ROOT/'tests/gcc'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(args):
    p=subprocess.run([str(a) for a in args],capture_output=True,text=True,timeout=120)
    assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
    return p

def main():
    work=Path(tempfile.mkdtemp(prefix='review-declarator-consumer-'))
    source=ROOT/'build-out/direct-gcc-inputs/gcc-source'
    config=ROOT/'build-out/direct-configure-ul9t208b/build/libiberty'
    fixture=TEST/'review-declarator-consumer.c'
    cc=ROOT/'tools/gcc-direct-cc.py'
    includes=['-DHAVE_CONFIG_H','-I'+str(config),'-I'+str(source/'include')]
    inputs=[ROOT/'seed-forth',ROOT/'010-lib.fth',cc,*sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))]
    inputs += [ROOT/'000-seed.hex0',ROOT/'141-archive.fth',*sorted((ROOT/'runtime/gcc-seed').rglob('*.c')),*sorted((ROOT/'runtime/gcc-seed').rglob('*.h'))]
    hashes={str(p.relative_to(ROOT)):sha(p) for p in inputs}
    original=[source/'libiberty'/(n+'.c') for n in ('spaces','dyn-string','xatexit','xexit','xmalloc')]
    source_inputs=[*original,config/'config.h',*[source/'include'/n for n in ('ansidecl.h','libiberty.h','dyn-string.h')]]
    source_hashes={str(p.relative_to(ROOT)):sha(p) for p in source_inputs}
    objs=[]
    for src in original:
        out=work/(src.stem+'.o')
        run([cc,'-c',*includes,src,'-o',out]);objs.append(out)
    outcomes=[]
    exe=work/'forth-only'
    run([cc,*includes,fixture,*objs,'-o',exe])
    result=run([exe])
    assert result.stdout=='PASS: original spaces, dyn-string, xatexit and xexit; 70 LIFO handlers\n',result.stdout
    outcomes.append({'mode':'forth-only','sha256':sha(exe),'stdout':result.stdout})
    print(result.stdout.strip(),flush=True)
    for opt in ('-O0','-O2'):
        for target in (False,True):
            exe=work/('host-'+('target' if target else 'source')+opt)
            run(['gcc','-std=c90','-pedantic-errors',opt,'-fno-pie','-no-pie',*includes,*(['-DREVIEW_DECLARATOR_HOST_TARGET'] if target else []),fixture,*(objs if target else original),'-o',exe])
            result=run([exe])
            assert result.stdout==outcomes[0]['stdout'],result.stdout
            outcomes.append({'mode':exe.name,'sha256':sha(exe),'stdout':result.stdout})
            print('PASS:',exe.name,flush=True)
    assert hashes=={str(p.relative_to(ROOT)):sha(p) for p in inputs},'compiler changed'
    assert source_hashes=={str(p.relative_to(ROOT)):sha(p) for p in source_inputs},'original source or configured header changed'
    report={'compiler_source_identity':run([cc,'--print-source-hash']).stdout.strip(),'source_closure_sha256':source_hashes,'compiler_sha256':hashes,'configuration_sha256':sha(config/'config.h'),'source_sha256':{str(p.relative_to(ROOT)):sha(p) for p in original},'fixture_sha256':sha(fixture),'script_sha256':sha(Path(__file__)),'object_sha256':{p.name:sha(p) for p in objs},'executions':outcomes,'work':str(work),'host_target_tools':False,'oracle_host':'gcc C90 O0/O2'}
    (TEST/'review-declarator-consumer-results.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')
    print(TEST/'review-declarator-consumer-results.json')
if __name__=='__main__':main()
