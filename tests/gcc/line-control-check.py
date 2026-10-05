#!/usr/bin/env python3
"""C line control: host CPP token oracle and seed/Forth production proofs."""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]
DRIVER=ROOT/'tools/gcc-direct-cc.py'
spec=importlib.util.spec_from_file_location('location_oracle',ROOT/'tests/gcc/review-source-location-check.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
def run(argv,data=None,status=0):
    p=subprocess.run([str(x) for x in argv],input=data,capture_output=True,cwd=ROOT,timeout=90)
    assert p.returncode==status,(argv,p.returncode,p.stdout,p.stderr)
    return p

def main():
    inputs=sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))+[ROOT/'010-lib.fth',DRIVER,Path(__file__)]
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    work=Path(tempfile.mkdtemp(prefix='line-control-',dir=ROOT/'build-out'))
    source=work/'input.c';records=[]
    cases={
      'prefix-whitespace':'\f\v #\f\v line 30 \"prefix.c\"\n__LINE__ __FILE__\n',
      'skipped-prefix':'#if 0\n#/**/line 30 \"v.c\"\n#/**/ 1 \"v.c\"\n#/**/endif\n__LINE__\n',
      'comment-prefix':'#/**/line 30 "v.c"\n__LINE__ __FILE__\n',
      'leading-comment-prefix':'/* prefix */ #line 30 "v.c"\n__LINE__ __FILE__\n',
      'multiline-prefix':'# /* one\ntwo */ line 30 "v.c"\n__LINE__ __FILE__\n',
      'number-only':'#line 40\n__LINE__ __FILE__\n__LINE__\n',
      'filename':'#line 91 "virtual.c"\n__LINE__ __FILE__\n#line 2\n__LINE__ __FILE__\n',
      'empty-filename':'#line 1 ""\n__LINE__ __FILE__\n',
      'decimal-leading-zero':'#line 000019\n__LINE__\n',
      'largest':'#line 2147483647\n__LINE__\n',
      'object-alias':'#define N 71\n#define NAME "logical.c"\n#define ALIAS N NAME\n#line ALIAS\n__LINE__ __FILE__\n',
      'function':'#define L(n,f) n f\n#line L(19,"function.c")\n__LINE__ __FILE__\n',
      'stringify':'#define STR1(s) #s\n#define STR(s) STR1(s)\n#define N 28\n#line N STR(generated.y)\n__LINE__ __FILE__\n',
      'paste':'#define P(a,b) a##b\n#line P(2,7)\n__LINE__\n',
      'builtin-operands':'#line 21 "prior.c"\n#line __LINE__ __FILE__\n__LINE__ __FILE__\n',
      'comments':'#line /*a*/ 44 /*b*/ "comment.c" /*c*/\n__LINE__ __FILE__\n',
      'multiline-comment':'#line 45 /*first\nsecond*/ "comment.c"\n__LINE__ __FILE__\n',
      'continuation':'#line \\\n 46 \\\n "continued.c"\n__LINE__ __FILE__\n',
      'continued-filename':'#line 47 "con\\\ntinued.c"\n__LINE__ __FILE__\n',
      'skipped':'#line 49 "kept.c"\n#if 0\n#line not valid !\n# 1 "unsupported.c"\n#endif\n__LINE__ __FILE__\n',
      'invocation':'#define L __LINE__\n#define F __FILE__\n#line 73 "macro.c"\nL F\nL F\n',
      'multiline-invocation':'#define A(a,b) a,b,__LINE__,__FILE__\n#line 80 "args.c"\nA(\n__LINE__,\n__LINE__)\n__LINE__\n',
      'condition':'#line 73 "condition.c"\n#if __LINE__ != 73\n#error incorrect line\n#endif\n__LINE__\n',
      'escapes':'#line 50 "quote\\\"slash\\\\tab\\tline\\n\\101\\x42.c"\n__LINE__ __FILE__\n',
      'simple-escapes':'#line 51 "\\a\\b\\f\\n\\r\\t\\v\\?\\\'\\\"\\\\.c"\n__FILE__\n',
      'filename-capacity':'#line 1 "'+('a'*1023)+'"\n__FILE__\n',
      'carriage-return':'#line 7 "crlf.c"\r\n__LINE__ __FILE__\r\n',
      'whitespace':'#line\t8\f"spaces.c"\v\n__LINE__ __FILE__\n',
      'no-final-newline':'#line 6 "end.c"\n__LINE__ __FILE__',
      'command-line':'#line COMMAND_LINE COMMAND_FILE\n__LINE__ __FILE__\n',
    }
    cases.update({'file-splice-comments-lf': '/* first */\\\n/* second */\n__LINE__ __FILE__\n', 'file-splice-comment-code-lf': '/* first */\\\n__LINE__ __FILE__\n', 'file-splice-comment-line-lf': '/* first */\\\n#line 51 "mapped.y"\n__LINE__ __FILE__\n', 'file-splice-source-whitespace-lf': 'int x; \\\n__LINE__ __FILE__\n', 'file-splice-initial-lf': '\\\n__LINE__ __FILE__\n', 'file-splice-directive-prefix-lf': '#\\\nline 61 "prefix.y"\n__LINE__ __FILE__\n', 'file-splice-skipped-lf': '#if 0\n/* first */\\\n/* second */\nint ignored;\n#endif\n__LINE__\n', 'file-splice-repeat-comments-lf': '#line 60 "outer.y"\n/*a*/\\\n/*b*/\\\n/*c*/ #line __LINE__ __FILE__\n__LINE__ __FILE__\n', 'file-splice-comments-crlf': '/* first */\\\r\n/* second */\r\n__LINE__ __FILE__\r\n', 'file-splice-comment-code-crlf': '/* first */\\\r\n__LINE__ __FILE__\r\n', 'file-splice-comment-line-crlf': '/* first */\\\r\n#line 51 "mapped.y"\r\n__LINE__ __FILE__\r\n', 'file-splice-source-whitespace-crlf': 'int x; \\\r\n__LINE__ __FILE__\r\n', 'file-splice-initial-crlf': '\\\r\n__LINE__ __FILE__\r\n', 'file-splice-directive-prefix-crlf': '#\\\r\nline 61 "prefix.y"\r\n__LINE__ __FILE__\r\n', 'file-splice-skipped-crlf': '#if 0\r\n/* first */\\\r\n/* second */\r\nint ignored;\r\n#endif\r\n__LINE__\r\n', 'file-splice-repeat-comments-crlf': '#line 60 "outer.y"\r\n/*a*/\\\r\n/*b*/\\\r\n/*c*/ #line __LINE__ __FILE__\r\n__LINE__ __FILE__\r\n'})
    for name,text in cases.items():
        source.write_text(text);flags=['-DCOMMAND_LINE=62','-DCOMMAND_FILE="command.c"']
        actual=run([DRIVER,'-E',*flags,source]).stdout
        if name=='simple-escapes':
            # GCC 14 ICEs on some control bytes in a presumed filename.
            assert module.tokens(actual)==[('string',bytes([7,8,12,10,13,9,11])+b"?'\"\\.c")],actual
            records.append({'case':name,'oracle':'explicit decoded bytes; host GCC14 ICE boundary'})
            continue
        expected=run(['cc','-E','-P',*flags,source]).stdout
        assert module.tokens(actual)==module.tokens(expected),(name,actual,expected)
        records.append({'case':name,'sha256':hashlib.sha256(actual).hexdigest()})
    (work/'real/sub').mkdir(parents=True)
    (work/'real/a.h').write_text('__LINE__ __FILE__\n#line 101 "virtual/header.y"\n__LINE__ __FILE__\n#define NEXT "sub/b.h"\n#include NEXT\n__LINE__ __FILE__\n')
    (work/'real/sub/b.h').write_text('__LINE__ __FILE__\n#line 301 "nested.y"\n__LINE__ __FILE__\n')
    source.write_text('#line 61 "virtual/main.y"\n#include "real/a.h"\n__LINE__ __FILE__\n#include "real/a.h"\n__LINE__ __FILE__\n')
    actual=run([DRIVER,'-E',source]).stdout;expected=run(['cc','-E','-P',source]).stdout
    assert module.tokens(actual)==module.tokens(expected),(actual,expected)
    records.append({'case':'nested-physical-includes','sha256':hashlib.sha256(actual).hexdigest()})
    bad=['1 /* unclosed','','UNKNOWN','0','2147483648','99999999999999999999999999999','-1','+1','1U','1.0','0x10','(1)','1+1','1 2','1 "a" "b"','1 L"a"','1 u8"a"','1 "unterminated','1 "a" tail','1 "\\x"','1 "\\x100"','1 "\\400"','1 "\\0"','1 "\\q"','1 "\\u0041"','1 "'+('a'*1024)+'"']
    for i,operand in enumerate(bad):
        source.write_text('#line '+operand+'\nint main(void){return 0;}\n');out=work/'previous.o';out.write_bytes(b'previous artifact\n')
        p=run([DRIVER,'-c',source,'-o',out],status=49)
        assert b'error 49' in p.stderr and out.read_bytes()==b'previous artifact\n',(i,p.stderr)
    for text in ['#define N 9\n#define NAME 30\n#define AME\n#line N\\\nAME\n', '#line 1\\\n2\n']:
        source.write_text(text+'__LINE__\n');out=work/'previous.i';out.write_bytes(b'previous text\n')
        run([DRIVER,'-E',source,'-o',out],status=49);assert out.read_bytes()==b'previous text\n'
    # Phase two deletes continuations before comments are recognized: split
    # comment delimiters and continued comments are ordinary (host CPP oracle).
    for data in [b'#/\\\n**/line 25 \"v.y\"\n__LINE__ __FILE__\n', b'#/\\\r\n**/line 25 \"v.y\"\r\n__LINE__ __FILE__\r\n', b'/\\\n*p*/ #line 25 \"v.y\"\n__LINE__ __FILE__\n', b'/\\\r\n*p*/ #line 25 \"v.y\"\r\n__LINE__ __FILE__\r\n', b'#// x \\\r\nline 30 \"v.y\"\r\n__LINE__ __FILE__\r\n', b'#// x \\\nline 30 \"v.y\"\n__LINE__ __FILE__\n', b'#line 10 // x \\\r\nmore\r\n__LINE__\r\n', b'#line 10 // continued \\\nmore\n__LINE__\n', b'#line 10 /* x *\\\n/\n__LINE__\n', b'#line 10 /* x *\\\r\n/ \"c.y\"\r\n__LINE__ __FILE__\r\n', b'int value; /\\\n* comment */\n__LINE__\n', b'int value; /\\\n/ comment\n__LINE__\n', b'int value; /\\\r\n* comment */\r\n__LINE__\r\n', b'int value; /\\\r\n/ comment\r\n__LINE__\r\n']:
        source.write_bytes(data)
        actual=run([DRIVER,'-E',source]).stdout;expected=run(['cc','-E','-P',source]).stdout
        assert module.tokens(actual)==module.tokens(expected),(data,actual,expected)
        records.append({'case':'comment-splice','sha256':hashlib.sha256(actual).hexdigest()})
    for data in [b'#\\\n 1 \"v.y\"\n', b'#li\\\nne 30 \"v.y\"\n', b'#li\\\r\nne 30 \"v.y\"\r\n']:
        source.write_bytes(data);out=work/'previous.i';out.write_bytes(b'previous text\n')
        run([DRIVER,'-E',source,'-o',out],status=49);assert out.read_bytes()==b'previous text\n'
    for data in [b'#define N 9\n#define NAME 25\n#define AME\nN\\\nAME\n', b'1\\\n2\n', b'#define N 9\r\n#define NAME 25\r\n#define AME\r\nN\\\r\nAME\r\n', b'1\\\r\n2\r\n']:
        source.write_bytes(data);out=work/'previous.i';out.write_bytes(b'previous text\n')
        run([DRIVER,'-E',source,'-o',out],status=49);assert out.read_bytes()==b'previous text\n'
    for directive in ['#/**/ 1 "v.c"', '# /* unclosed', '#\rline 30 \"v.c\"', '\r#line 30 \"v.c\"']:
        source.write_text(directive+'\n__LINE__ __FILE__\n');out=work/'previous.i';out.write_bytes(b'previous text\n')
        run([DRIVER,'-E',source,'-o',out],status=49);assert out.read_bytes()==b'previous text\n'
    for directive in ['# 99 "marker.c"','#line 1 "a" extra']:
        source.write_text(directive+'\nint main(void){return 0;}\n');out=work/'previous.i';out.write_bytes(b'previous text\n')
        run([DRIVER,'-E',source,'-o',out],status=49);assert out.read_bytes()==b'previous text\n'
    (work/'real/a.h').write_text('#line 701 "header.y"\nstatic int header_line = __LINE__;\nstatic const char header_file[] = __FILE__;\n#include "sub/b.h"\nstatic int header_return = __LINE__;\n')
    (work/'real/sub/b.h').write_text('#line 901 "nested.y"\nstatic int nested_line = __LINE__;\nstatic const char nested_file[] = __FILE__;\n')
    source.write_text('''#include <string.h>
#define LOCATION __LINE__
#line 401 "grammar.y"
#include "real/a.h"
static int source_line = __LINE__;
static const char source_file[] = __FILE__;
int main(void) {
 if(header_line != 701 || header_return != 704 || nested_line != 901) return 1;
 if(source_line != 402 || LOCATION != 406) return 2;
 if(strcmp(header_file,"header.y") || strcmp(nested_file,"nested.y")) return 3;
 if(strcmp(source_file,"grammar.y")) return 4;
 return 0;
}
''')
    exe=work/'line-control';run([DRIVER,source,'-o',exe]);run([exe])
    modules=[ROOT/'010-lib.fth']+sorted(p for p in ROOT.glob('[0-9][0-9][0-9]-cc-*.fth') if p.name not in ('120-cc-main.fth','140-cc-link.fth'))
    vocab=b'\n'.join(p.read_bytes() for p in modules)
    first=b'#line 16 "stale.y"\n__LINE__ __FILE__\n';second=b'__LINE__ __FILE__\n'
    def array(name,data):return b'create '+name+b'\n'+b''.join(b'[lit] '+str(c).encode()+b' c,\n' for c in data)
    script=array(b'first',first)+array(b'second',second)+b': check-input cc-in-len ! [lit] 0 begin, dup cc-in-len @ < while, 2dup + c@ over cc-in-buf + c! 1+ repeat, 2drop cc-preprocess [lit] 1 cc-src-buf cc-src-len @ write drop ;\ncc-sysv-object-enable\nfirst [lit] '+str(len(first)).encode()+b' check-input\nsecond [lit] '+str(len(second)).encode()+b' check-input\nbye\n'
    result=run([ROOT/'seed-forth'],vocab+b'\n'+script)
    assert module.tokens(result.stdout)==[b'16',('string',b'stale.y'),b'1',('string',b'<stdin>')],result.stdout
    assert hashes=={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    report={'status':'PASS','source_sha256':hashes,'token_cases':records,'reject49_preserves_output':len(bad)+15,'repeated_preprocess':'same seed process resets logical state','production':'Forth compiler/runtime/linker execution validates nested line/name state','scope':'ISO decimal range; ordinary filename byte strings up to 1023 decoded non-NUL bytes; GNU numeric markers, split directive names and token-joining nonliteral continuations remain unsupported; comment continuations follow phase two; diagnostics remain flattened'}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: C #line macro operands, logical locations, physical includes, Forth execution, resets and failure preservation')
    print(work/'report.json')
if __name__=='__main__':main()
