#!/usr/bin/env python3
"""Forth-built scripted faults for the bounded Flex stream group."""
from pathlib import Path
import hashlib,importlib.util,json,tempfile
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('stdio_check',ROOT/'tests/gcc/stdio-check.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
(ROOT/'build-out').mkdir(exist_ok=True);OUT=Path(tempfile.mkdtemp(prefix='stream-flex-fault-',dir=ROOT/'build-out'))
sources=[ROOT/'runtime/gcc-seed'/(n+'.c') for n in ['memory','string','alloc','strerror','stdio']]+[ROOT/'tests/gcc/stream-flex-faults.c']
objects=[]
for source in sources:
    obj=OUT/(source.stem+'.o');module.run([ROOT/'tests/gcc/sysv-object-compile.sh',source,obj,ROOT/'runtime/gcc-seed/include']);objects.append(obj)
driver=''
for name,builder in [('errno','cc-sysrt-errno-object'),('start','cc-sysrt-start-object')]:
    obj=OUT/(name+'.o');driver+=module.path_word(name+'-output',obj)+builder+' '+name+'-output cc-obj-write\n';objects.append(obj)
module.forth(module.BASE+['081-cc-object.fth','122-cc-sysv-runtime.fth'],driver+'bye\n')
executable=OUT/'faults';module.link(objects,executable)
for scenario in range(1,7):module.run([executable,str(scenario)])
report={'state':'pass','scenarios':['freopen close/open/dup2 EINTR and original descriptor','freopen open failure closes stream','freopen dup2 failure preserves error','fgets new error versus sticky error','fseek pushback/overflow/EINTR/nonseekable failure/EOF reset','fgets size/access boundaries'],'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[Path(__file__).resolve()]},'executable_sha256':hashlib.sha256(executable.read_bytes()).hexdigest()}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: six Forth-built stream syscall-fault scenarios');print(OUT/'report.json')
