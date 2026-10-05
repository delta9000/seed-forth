#!/usr/bin/env python3
"""Original regex.c raw compilation and separately configured malloc-mode behavior.

No original source is rewritten. The behavior build enables upstream's documented
REGEX_MALLOC mode because the raw configured unit leaves alloca unresolved and
undeclared. It does not claim to resolve that raw-library integration boundary.
"""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
PINS={'libiberty/regex.c':'a2bc8e7f48236a32d218c7847f4f27a70e03e3da0b77188661c09e10bdf0520b',
      'include/ansidecl.h':'8d761202d371342ceff509b7a07cdbbf0ae767c03e3bd9abe57f35b9b15e6a73',
      'include/xregex.h':'d6dcb6c0a33393ce7d662d029c934430959979ef22f166aeccfbab986749197f',
      'include/xregex2.h':'1ae8f6e89450a4092fa45c926bb889be39e129305b3fd3a8e68d46342b0b023a'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--source-root',required=True,type=Path);ap.add_argument('--config-dir',required=True,type=Path);ap.add_argument('--work',type=Path);args=ap.parse_args()
    source=args.source_root.resolve();config=args.config_dir.resolve();work=(args.work or Path(tempfile.mkdtemp(prefix='knr-regex-',dir=ROOT/'build-out'))).resolve();work.mkdir(parents=True,exist_ok=True)
    assert all(sha(source/n)==h for n,h in PINS.items())
    config_hash=sha(config/'config.h');steps=[]
    def run(label,cmd):
        p=subprocess.run(list(map(str,cmd)),cwd=ROOT,capture_output=True,timeout=600)
        (work/(label+'.stdout')).write_bytes(p.stdout);(work/(label+'.stderr')).write_bytes(p.stderr)
        steps.append({'label':label,'command':list(map(str,cmd)),'status':p.returncode});(work/'steps.json').write_text(json.dumps(steps,indent=2)+'\n')
        assert p.returncode==0,(label,p.returncode,p.stderr)
        return p.stdout
    identity=subprocess.check_output([ROOT/'tools/gcc-direct-cc.py','--print-source-hash'],text=True).strip()
    test_hash=sha(Path(__file__))
    cc=ROOT/'tools/gcc-direct-cc.py';flags=['-DHAVE_CONFIG_H','-I'+str(config),'-I'+str(source/'include')]
    raw=work/'regex-raw.o';run('raw-compile',[cc,*flags,'-c',source/'libiberty/regex.c','-o',raw])
    raw_undefined=run('raw-symbols',['nm','-u',raw]).decode()
    assert ' U alloca\n' in raw_undefined,'raw integration boundary changed; inspect before updating proof'
    obj=work/'regex-malloc.o';run('malloc-mode-compile',[cc,*flags,'-DREGEX_MALLOC','-c',source/'libiberty/regex.c','-o',obj])
    undefined=run('malloc-mode-symbols',['nm','-u',obj]).decode();assert ' alloca\n' not in undefined
    # Expected compile/match classes are independent of output comparisons.
    # Exact capture offsets, errors and error text are compared with host builds.
    cases=[
      ('abc','zabcx',1,0,0,0),('abc','abx',1,0,0,1),
      ('(ab)(c+)','zzabcccz',1,0,0,0),('(a(b|c))*d','abacabd',1,0,0,0),
      ('(a(b|c))*d','abacabe',1,0,0,1),('([a-z]+)-([0-9]{2,4})','tag-123!',1,0,0,0),
      ('(a|aa)+b','aaaaab',1,0,0,0),('(a|aa)+b','aaaaac',1,0,0,1),
      ('^([a-z]+)$','HELLO',3,0,0,0),('[[:digit:]]+','ab123cd',1,0,0,0),
      ('[[:space:]]+','a \t b',1,0,0,0),('^[^x]+$','abc',1,0,0,0),
      ('^[^x]+$','abxc',1,0,0,1),('a{2,4}','zaaaaz',1,0,0,0),
      ('a*','bbb',1,0,0,0),('^$','',1,0,0,0),
      ('^b$','a\nb\nc',5,0,0,0),('^b$','a\nb\nc',1,0,0,1),
      ('^abc','abc',1,1,0,1),('abc$','abc',1,2,0,1),
      ('\\(ab\\)\\1','zababq',0,0,0,0),('\\(ab\\)\\1','zabacq',0,0,0,1),
      ('(ab)\\1','zababq',1,0,0,0),('(a(b|c))\\1','zababq',1,0,0,0),
      ('(a(b|c))\\1','zabacq',1,0,0,1),('[','abc',1,0,1,0),
      ('(','abc',1,0,1,0),('a{4,2}','aaaa',1,0,1,0),
      ('[z-a]','a',1,0,1,0),('\\1','a',0,0,1,0),
    ]
    c='#include <stddef.h>\n#include <stdio.h>\n#include <string.h>\n#include "xregex.h"\n'
    c+='struct C{const char *pattern,*text;int flags,eflags,bad,nomatch;};\nstatic struct C cases[]={\n'
    for p,t,f,e,b,n in cases:c+='{'+json.dumps(p)+','+json.dumps(t)+f',{f},{e},{b},{n}'+'},\n'
    c+='};\nint main(void){regex_t r;regmatch_t m[8];char message[256];size_t length;int i,j,code,status;for(i=0;i<30;i++){memset(&r,0,sizeof(r));code=regcomp(&r,cases[i].pattern,cases[i].flags);if((code!=0)!=cases[i].bad)return 10+i;length=regerror(code,&r,message,sizeof(message));printf("%d %d %lu %s",i,code,(unsigned long)length,message);if(!code){for(j=0;j<8;j++){m[j].rm_so=-99;m[j].rm_eo=-99;}status=regexec(&r,cases[i].text,8,m,cases[i].eflags);if((status==REG_NOMATCH)!=cases[i].nomatch)return 50+i;if(status!=0&&status!=REG_NOMATCH)return 90+i;printf(" %d",status);if(status==0)for(j=0;j<8;j++)printf(" %d:%d",(int)m[j].rm_so,(int)m[j].rm_eo);regfree(&r);}printf("\\n");}return 0;}\n'
    c=c.replace('i<30','i<'+str(len(cases)))
    harness=work/'witness.c';harness.write_text(c)
    exe=work/'forth-witness';run('forth-link',[cc,'-I'+str(source/'include'),obj,harness,'-o',exe]);result=run('forth-run',[exe])
    for opt in ('-O0','-O2'):
        host_obj=work/('host-regex'+opt+'.o');host=os.environ.get('CC','cc')
        run('host-compile'+opt,[host,'-std=gnu90',opt,'-fno-pie',*flags,'-DREGEX_MALLOC','-c',source/'libiberty/regex.c','-o',host_obj])
        host_exe=work/('host-witness'+opt);run('host-link'+opt,[host,'-std=c90',opt,'-fno-pie','-no-pie','-I'+str(source/'include'),host_obj,harness,'-o',host_exe])
        reference=run('host-run'+opt,[host_exe]);assert result==reference,(opt,'behavior mismatch')
    assert all(sha(source/n)==h for n,h in PINS.items());assert sha(config/'config.h')==config_hash
    assert identity==subprocess.check_output([cc,'--print-source-hash'],text=True).strip()
    assert test_hash==sha(Path(__file__))
    report={'compiler_runtime_identity':identity,'test_sha256':test_hash,'original_source_revision':'944765863eec87a9f37e297994fd2af960397138','pins':PINS,'config_sha256':config_hash,'source_rewritten':False,'raw':{'sha256':sha(raw),'bytes':raw.stat().st_size,'undefined':raw_undefined},'behavior':{'upstream_mode':'REGEX_MALLOC','object_sha256':sha(obj),'bytes':obj.stat().st_size,'cases':len(cases),'output_sha256':hashlib.sha256(result).hexdigest(),'runtime':'actual Forth-built seed runtime; no host target artifacts','host_oracles':['O0','O2'],'separate_from_raw_alloca_integration':True},'steps':steps,'limits':'bounded cases only; not complete regex conformance or raw full-library execution'}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: unchanged original regex.c raw compile; separate upstream malloc-mode behavior agrees with host O0/O2 on30 cases');print(work/'report.json')
if __name__=='__main__':main()
