#!/usr/bin/env python3
"""Literal line continuations remove bytes while retaining source provenance."""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
DRIVER=ROOT/'tools/gcc-direct-cc.py'
spec=importlib.util.spec_from_file_location('source_location_tokens',ROOT/'tests/gcc/source-location-check.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


def run(args,stdout=None):
    result=subprocess.run(args,capture_output=True,timeout=60)
    assert result.returncode==0,(args,result.returncode,result.stdout,result.stderr)
    if stdout is not None: assert result.stdout==stdout,(args,result.stdout,stdout)
    return result.stdout


def main():
    work=Path(tempfile.mkdtemp(prefix='literal-splice-',dir=ROOT/'build-out'))
    inputs=[ROOT/'040-cc-prep.fth',ROOT/'124-cc-target.fth',ROOT/'tools/gcc-direct-cc.py',Path(__file__),ROOT/'tests/gcc/source-location-check.py']
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    splice=chr(92)+'\n'
    cases=[
      'const char *s="'+splice+'A'+splice+'B";\n__LINE__\n',
      "int c='A"+splice+"';\n__LINE__\n",
      '#define TEXT "a'+splice+'b"\nTEXT\n__LINE__\n',
      '#define ID(x) x\nID("a'+splice+'b")\n__LINE__\n',
      '#define STR(x) #x\nSTR("a'+splice+'b")\n__LINE__\n',
      '#define STR(x) #x\nSTR(a'+splice+'b)\n__LINE__\n',
      '#define BOTH(x) x,#x\nBOTH("a'+splice+'b")\n__LINE__\n',
      '#if 0\n"a'+splice+'b"\n#endif\n__LINE__\n',
      '"a'+splice+'b" "c'+splice+'d"\n__LINE__\n',
      '#define STR(x) #x\n#define WRAP(x) STR(x)\nWRAP("a'+splice+'b")\n__LINE__\n',
    ]
    # Splicing precedes escape pairing: the last slash is removed for
    # both odd and even runs, leaving the previous slash to escape b.
    for count in range(1,9):
        token='"a'+chr(92)*count+'\n'+'b"'
        cases.append('const char *s='+token+';\n__LINE__\n')
        cases.append('#define STR(x) #x\nSTR('+token+')\n__LINE__\n')
    for argument in ['a'+splice,splice,splice+'a', 'a'+splice+'  ', ' '+splice+' ']:
        cases.append('#define STR(x) #x\nSTR('+argument+')\n__LINE__\n')
    records=[]
    source=work/'input.c'
    for i,text in enumerate(cases):
        source.write_text(text)
        actual=run([DRIVER,'-E',source]);expected=run(['cc','-E','-P',source])
        assert module.tokens(actual)==module.tokens(expected),(i,actual,expected)
        records.append({'case':i,'sha256':hashlib.sha256(actual).hexdigest()})
    header=work/'header.h'
    header.write_text('#define TEXT "header'+splice+'text"\n')
    source.write_text('#include "header.h"\nTEXT\n__LINE__\n')
    assert module.tokens(run([DRIVER,'-E',source]))==module.tokens(run(['cc','-E','-P',source]))
    source.write_text('#define H "hea'+splice+'der.h"\n#include H\nTEXT\n__LINE__\n')
    assert module.tokens(run([DRIVER,'-E',source]))==module.tokens(run(['cc','-E','-P',source]))
    source.write_text('#include <stdio.h>\n#include <string.h>\n#define STR(x) #x\nint main(void){\nputs("'+splice+'A'+splice+'B");\nif(strcmp(STR("a'+splice+'b"),"\\\"ab\\\""))return 1;\nif(\'A'+splice+'\'!=65)return 2;\nreturn 0;\n}\n')
    exe=work/'literal-splice';run([DRIVER,source,'-o',exe]);run([exe],stdout=b'AB\n')
    assert hashes=={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    report={'status':'PASS','token_cases':records,'include_cases':2,'production':'Forth compiler/runtime/linker emits AB plus one puts newline; stringification and character literal values match','scope':'Literal and raw stringification continuations; general outside-token phase2 splicing remains outside this increment','source_sha256':hashes}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: literal/character/stringified continuations, source line counts, includes and Forth-only output')
    print(work/'report.json')


if __name__=='__main__':main()
