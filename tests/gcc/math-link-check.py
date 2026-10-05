#!/usr/bin/env python3
"""Builtin -lm is an ordered Forth archive, not implicit libc or host libm."""
import hashlib,importlib.util,json,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(tempfile.mkdtemp(prefix='math-link-',dir=ROOT/'build-out'))
CC=[sys.executable,str(ROOT/'tools/gcc-direct-cc.py')]
commands=[]
def run(args,ok=True):
    p=subprocess.run(list(map(str,args)),capture_output=True,timeout=180)
    commands.append({'arguments':list(map(str,args)),'returncode':p.returncode,'stderr':p.stderr.decode(errors='replace')})
    (OUT/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    assert (p.returncode==0)==ok,(args,p.returncode,p.stderr)
    if ok:assert not p.stderr,(args,p.stderr)
    return p
source=OUT/'main.c';source.write_text('#include <math.h>\nint main(void) { return log(1.0) != 0.0 || exp(0.0) != 1.0; }\n')
output=OUT/'program'
run(CC+[source,'-lm','-o',output]);run([output])
# Omitting the explicit library and placing it before its consumer both fail.
for args in ([source],['-lm',source],['-lfoo',source],['-l',source],['-l','m',source],
             ['-L.',source,'-lm'],['-c',source,'-lm'],['-E',source,'-lm'],
             ['--print-source-hash','-lm'],['-lm']):
    output.write_bytes(b'preserve-output');run(CC+args+['-o',output],False)
    assert output.read_bytes()==b'preserve-output'
run(CC+[source,'-lm','-lm','-o',output]);run([output])
# Inspect the actual archive emitter without a host assembler/archive producer.
spec=importlib.util.spec_from_file_location('seed_math_driver',ROOT/'tools/gcc-direct-cc.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
work=OUT/'snapshot';work.mkdir();toolchain=mod.Toolchain(work)
archive=toolchain.math_archive();assert archive.read_bytes().startswith(b'!<arch>\n')
assert run(['ar','t',archive]).stdout==b'math.o\n'
assert (work/'math.o').read_bytes()[:5]==b'\x7fELF\x02'
runtime=toolchain.runtime_objects();assert not any(p.name=='math.o' for p in runtime)
libc=toolchain.runtime_archive(runtime);assert b'math.o' not in run(['ar','t',libc]).stdout.splitlines()
# Explicit libm is allowed under -nostdlib, but supplies neither startup nor
# errno nor syscall support. Those objects must be explicitly supplied here.
start=OUT/'start.c';start.write_text('#include <math.h>\n#include <seed-syscall.h>\nvoid _start(void) { long status = log(1.0) != 0.0; __seed_syscall6(60,status,0,0,0,0,0); for (;;) {} }\n')
supplied=[p for p in runtime if p.name in ('syscall.o','errno.o')]
run(CC+['-nostdlib',start,'-lm']+supplied+['-o',output]);run([output])
output.write_bytes(b'preserve-output');run(CC+['-nostdlib',start,'-lm','-o',output],False)
assert output.read_bytes()==b'preserve-output'
# A missing source in the immutable private snapshot cannot become an empty
# archive. It is rejected before any archive is published.
missing=OUT/'missing';missing.mkdir();other=mod.Toolchain(missing)
(other.runtime/'math.c').unlink()
try:other.math_archive()
except mod.Failure:pass
else:raise AssertionError('missing math source accepted')
assert not (missing/'libm.a').exists()
report={'compiler_source_identity':toolchain.identity,'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
        'object_sha256':hashlib.sha256((work/'math.o').read_bytes()).hexdigest(),
        'producer':'Forth compiler/object writer/archive writer/linker','host_ar':'inspection only',
        'runtime_math_member':False,'nostdlib_explicit_math':True,'ordered_archive':True,
        'atomic_failure':True,'commands':len(commands)}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS literal -lm: genuine math.o archive, ordered lazy selection, explicit nostdlib, rejected unsupported options, atomic failures')
print(OUT/'report.json')
