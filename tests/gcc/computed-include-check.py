#!/usr/bin/env python3
"""Computed include operands must consume genuine files or fail explicitly."""
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


def run(args,status=0):
    result=subprocess.run(args,capture_output=True,timeout=60)
    assert result.returncode==status,(args,result.returncode,result.stdout,result.stderr)
    return result


def main():
    work=Path(tempfile.mkdtemp(prefix='computed-include-',dir=ROOT/'build-out'))
    (work/'headers/nested').mkdir(parents=True)
    header=work/'headers/a.h'
    header.write_text('#ifndef A_INCLUDED\n#define A_INCLUDED\n#define INCLUDED_VALUE 41\n__FILE__ __LINE__\n#define NESTED "nested/b.h"\n#include NESTED\n#endif\n')
    (work/'headers/nested/b.h').write_text('nested_header __FILE__ __LINE__\n')
    (work/'headers/angle.h').write_text('angle_header __FILE__ __LINE__\n')
    # Computed string names keep backslash spellings, including escaped quotes.
    (work/'headers/quoted\\"name.h').write_text('escaped_quote_header\n')
    source=work/'input.c'
    tests=[
      '#define H "a.h"\n#include H\nINCLUDED_VALUE\n',
      '#define H "a.h"\n#define ALIAS H\n#include ALIAS\n',
      '#define STR1(x) #x\n#define STR(x) STR1(x)\n#include STR(a.h)\n',
      '#define H(x) x\n#include H("a.h")\n',
      '#define ANGLE <angle.h>\n#include ANGLE\n',
      '#include COMMAND_HEADER\n',
      '#define H "a.h"\n#include H /* after operand */\n__LINE__\n',
      '#define H "a.h"\n#include \\\n H\n__LINE__\n',
      '#define H "quoted\\"name.h"\n#include H\n',
      '#if 0\n#include NOT_DEFINED\n#endif\nokay\n',
    ]
    records=[]
    for i,text in enumerate(tests):
        source.write_text(text)
        flags=['-I'+str(work/'headers'),'-DCOMMAND_HEADER="a.h"']
        actual=run([DRIVER,'-E',*flags,source]).stdout
        expected=run(['cc','-E','-P',*flags,source]).stdout
        assert module.tokens(actual)==module.tokens(expected),(i,actual,expected)
        records.append({'case':i,'output_sha256':hashlib.sha256(actual).hexdigest()})
    bad=[
      '#include UNKNOWN\n', '#define H 17\n#include H\n',
      '#define H "a.h" "angle.h"\n#include H\n',
      '#define H "a.h" extra\n#include H\n',
      '#define H ""\n#include H\n', '#define H <angle.h\n#include H\n',
      '#define H\n#include H\n', '#define H H\n#include H\n',
      '#define H "not-present.h"\n#include H\n',
      '#define H < angle.h>\n#include H\n',
      '#define H(x) <x>\n#include H(angle.h)\n',
    ]
    for text in bad:
        source.write_text(text);out=work/'previous.o';out.write_bytes(b'previous object\n')
        result=run([DRIVER,'-c','-I'+str(work/'headers'),source,'-o',out],30)
        assert b'error 30' in result.stderr and out.read_bytes()==b'previous object\n'
    # A real program depends on the macro-selected header, so omission cannot
    # masquerade as preprocessing success.
    header.write_text('#define INCLUDED_VALUE 41\n')
    source.write_text('#define H "a.h"\n#include H\nint main(void){return INCLUDED_VALUE==41?0:1;}\n')
    exe=work/'program';run([DRIVER,'-I'+str(work/'headers'),source,'-o',exe]);run([exe])
    gcc=ROOT/'build-out/direct-gcc-inputs/gcc-source/gcc'
    target=gcc/'config/i386/i386-modes.def'
    target_proof=None
    if target.is_file():
        wanted='0141dec67f7141c1f2bb4096ad18fb2a7628f4a7ea5258acd9dc736491c6330d'
        assert hashlib.sha256(target.read_bytes()).hexdigest()==wanted
        source.write_text('#define EXTRA_MODES_FILE "config/i386/i386-modes.def"\n#include EXTRA_MODES_FILE\n')
        actual=run([DRIVER,'-E','-I'+str(gcc),source]).stdout
        expected=run(['cc','-E','-P','-I'+str(gcc),source]).stdout
        assert module.tokens(actual)==module.tokens(expected)
        for marker in [b'ieee_extended_intel_96_format',b'ieee_quad_format',b'CCGC',b'CCFPU',b'TARGET_128BIT_LONG_DOUBLE']:
            assert marker in actual,marker
        target_proof={'input_sha256':wanted,'all_original_tokens_match_host':True,'output_sha256':hashlib.sha256(actual).hexdigest()}
        assert hashlib.sha256(target.read_bytes()).hexdigest()==wanted
    else:
        print('SKIP: original pinned i386 modes input absent')
    inputs=[ROOT/'040-cc-prep.fth',ROOT/'124-cc-target.fth',ROOT/'tools/gcc-direct-cc.py',Path(__file__),ROOT/'tests/gcc/source-location-check.py']
    report={'status':'PASS','positive_cpp_cases':records,'rejections_preserve_output':len(bad),'production':'Forth compiler/runtime/linker executable depends on actual computed header','target_i386':target_proof,'scope':'Computed quoted strings and whitespace-free angle token results; internal computed-angle whitespace explicitly rejected','source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: computed include macro expansion/search/provenance, explicit failures, Forth execution and original i386 definitions')
    print(work/'report.json')


if __name__=='__main__':main()
