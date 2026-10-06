#!/usr/bin/env python3
"""Forth runtime-aware/raw entry tests plus a separate host ABI oracle."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
(ROOT/'build-out').mkdir(exist_ok=True)
OUT=Path(tempfile.mkdtemp(prefix='startup-check-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
def run(args,status=0,**kwargs):
 r=subprocess.run([str(x) for x in args],capture_output=True,timeout=120,**kwargs)
 assert r.returncode==status,(args,r.returncode,r.stdout,r.stderr)
 return r
def word(name,path):return 'create '+name+'\n'+''.join('[lit] '+str(x)+' c,\n' for x in os.fsencode(path)+b'\0')
identity=run(CC+['--print-source-hash']).stdout.decode().strip()
exe=OUT/'startup';run(CC+['-o',exe,ROOT/'tests/gcc/startup-check.c'])
cases=['program','/a/b/program','relative/path','/ends/in/slash/','']
for name in cases:
 args=[name,'left','two words','']
 # Force fork/exec: Python posix_spawn rejects the intentional empty argv[0].
 r=run(args,executable=exe,start_new_session=True)
 expected=name.rsplit('/',1)[-1]+'\n4\n'+''.join('['+arg+']\n' for arg in args)
 assert r.stdout.decode()==expected and not r.stderr,(name,r.stdout,r.stderr)
envp_exe=OUT/'startup-envp';run(CC+['-static',ROOT/'tests/gcc/startup-envp-check.c','-o',envp_exe])
envp_env=shutil.which('env')
assert envp_env,'env(1) is required for the controlled envp environment'
r=run([envp_env,'-i','FOO=bar','SEED_ENVP=two words',envp_exe,'x','y'])
assert r.stdout.decode()=='3 2\n' and not r.stderr,(r.stdout,r.stderr)
r=run([envp_env,'-i','FOO=bar','SEED_ENVP=two words','OTHER=1',envp_exe])
assert r.stdout.decode()=='1 3\n' and not r.stderr,(r.stdout,r.stderr)
r=run([envp_env,'-i',envp_exe],status=4)
program=b'\n'.join((ROOT/name).read_bytes() for name in ['010-lib.fth','020-cc-arena.fth','030-cc-io.fth','081-cc-object.fth','122-cc-sysv-runtime.fth'])
script=''
for name,builder in [('raw-start','cc-sysrt-start-object'),('runtime-start','cc-sysrt-runtime-start-object')]:
 script+=word(name,OUT/(name+'.o'))+builder+' '+name+' cc-obj-write\n'
run([ROOT/'seed-forth'],input=program+b'\n'+script.encode()+b'bye\n')
raw=OUT/'raw.c';raw.write_text('int main(int argc,char **argv){return argc==2 && argv[0] && argv[1][0]==\'x\' && argv[2]==0 ? 37:9;}\n')
run(CC+['-c','-o',OUT/'raw.o',raw]);run(CC+['-nostdlib','-o',OUT/'raw',OUT/'raw-start.o',OUT/'raw.o']);run([OUT/'raw','x'],status=37)
report={'compiler_source_identity':identity,'argv_variants':len(cases),'envp_third_argument_passed':True,'raw_entry_without_runtime_passed':True,'host_abi_oracles':[]}
host=shutil.which('gcc')
if host:
 fixture=OUT/'host-abi.c';fixture.write_text('''static int saved_count; static char **saved_args; static int bad;
void __seed_init_runtime(int count,char **args) {
 if (((unsigned long)__builtin_frame_address(0)&15UL)!=0) bad=1;
 saved_count=count; saved_args=args;
}
/* The runtime entry passes main's result to the C library exit. */
void exit(int status) {
 __asm__ volatile ("syscall" : : "a"(60L), "D"((long)status) : "rcx", "r11", "memory");
 for (;;) { }
}
int main(int count,char **args,char **envp) {
 if (((unsigned long)__builtin_frame_address(0)&15UL)!=0) return 2;
 return bad || count!=saved_count || args!=saved_args || count!=3 || args[1][0]!='a' || args[2][0]!='b' || args[3]!=0 || envp!=args+count+1;
}
''')
 for optimization in ['-O0','-O2']:
  target=OUT/('host-abi'+optimization[1:]);run([host,'-std=c90','-Wall','-Wextra','-Werror',optimization,'-fno-pie','-no-pie','-fno-stack-protector','-nostdlib','-static',fixture,OUT/'runtime-start.o','-o',target]);run([target,'a','b']);report['host_abi_oracles'].append({'optimization':optimization,'entry_alignment_and_arguments_passed':True})
assert identity==run(CC+['--print-source-hash']).stdout.decode().strip(),'compiler changed during test'
report['source_sha256']={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ['122-cc-sysv-runtime.fth','tools/gcc-direct-cc.py','runtime/gcc-seed/startup.c','runtime/gcc-seed/include/stdlib.h','tests/gcc/startup-check.c','tests/gcc/startup-envp-check.c','tests/gcc/startup-check.py']}
report['artifact_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [exe,envp_exe,OUT/'raw-start.o',OUT/'runtime-start.o',OUT/'raw']}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: runtime program name/argc/argv/envp, raw entry, host ABI O0/O2:',bool(host));print(OUT/'report.json')
