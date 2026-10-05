#!/usr/bin/env python3
"""Source-text continuations at token boundaries: host CPP token oracle.

binutils 2.30 bfd/cofflink.c continues a call after a comma,
`addend,\\<newline><tabs>...`.  C translation phase two deletes the
backslash-newline; the walker instead emits the physical newline, which is
equivalent whenever the bytes on either side cannot join into one token:
whitespace (or the end of input) after the run of continuations, or
whitespace, a whole-token punctuator or a complete block comment before it.
Inside comments, and between the bytes of a comment delimiter, phase two
simply deletes the continuation (`*\\<newline>/` closes a comment, a `//`
comment continues).  Splices that would join an identifier, number or
multi-byte punctuator, or split a directive name, remain rejected49 and leave
a previous output untouched.
"""
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


S='\\\n'
ACCEPT={
  # Reduced from bfd/cofflink.c (_bfd_relocate_contents call).
  'cofflink-call':'int f(int,long,int);\nint g(void){\n  return f (1,\n\t\t(long) 2,'+S+'\t\t3);\n}\n__LINE__\n',
  'comma-ident':'int x,'+S+'y;\n__LINE__\n',
  'semicolon':'int x;'+S+'int y;\n__LINE__\n',
  'parens':'int v=('+S+'1)'+S+';\n__LINE__\n',
  'brackets-braces':'int a['+S+'2]'+S+'={'+S+'1,2}'+S+';\n__LINE__\n',
  'tilde':'int t=~'+S+'0;\n__LINE__\n',
  'before-whitespace':'int x'+S+' ;\n__LINE__\n',
  'before-tab':'x+'+S+'\ty\n__LINE__\n',
  'before-formfeed':'x='+S+'\fy\n__LINE__\n',
  'before-blank-line':'x='+S+'\ny\n__LINE__\n',
  'chain-before-whitespace':'x='+S+S+S+' y\n__LINE__\n',
  'chain-after-comma':'f(a,'+S+S+'b)\n__LINE__\n',
  'end-of-input':'int x;\nx'+S,
  'macro-arguments':'#define F(a,b) a+b+__LINE__\nF(1,'+S+'\t2)\n__LINE__\n',
  'macro-name-then-args':'#define F(a,b) a+b\nF'+S+' (1,'+S+'2)\n__LINE__\n',
  'macro-name-space-splice':'#define F(a,b) a+b\nF '+S+'(1,2)\n__LINE__\n',
  'macro-name-splice-paren':'#define F(a,b) a+b\nF'+S+S+'(1,2)\n__LINE__\n',
  'macro-name-crlf-paren':'#define F(a,b) a+b\r\nF\\\r\n (1,2)\r\n__LINE__\r\n',
  'macro-name-not-call':'#define F(a,b) a+b\nF'+S+' x\n__LINE__\n',
  'macro-argument-paren':'#define ID(x) x\nID('+S+'q)\n__LINE__\n',
  'before-hash-not-directive':'x,'+S+' #define\n__LINE__\n',
  'skipped-group':'#if 0\nf(a,'+S+'\tb);\nx'+S+' y\n#endif\n__LINE__\n',
  'skipped-else':'#if 1\n__LINE__\n#else\nf(a,'+S+'b);\n#endif\n__LINE__\n',
  'crlf-comma':'f(a,\\\r\n\tb)\r\n__LINE__\r\n',
  'crlf-chain':'x=\\\r\n\\\r\n y\r\n__LINE__\r\n',
  # Phase two deletes continuations before comments are recognized.
  'comment-banner':'/****************\\\n * gas/flonum.h  *\n ****************/\nint z;\n__LINE__\n',
  'comment-inner':'/* a'+S+' b */ int x;\n__LINE__\n',
  'comment-split-close':'/* a *'+S+'/ int x;\n__LINE__\n',
  'comment-split-close-chain':'/* a *'+S+S+'/ int x; /* *'+S+'*/ int y;\n__LINE__\n',
  'comment-star-not-close':'/* a *'+S+'x */ int x;\n__LINE__\n',
  'comment-split-open':'x /'+S+'* c */ y\n__LINE__\n',
  'comment-split-open-chain':'x /'+S+S+'* c *'+S+'/ y\n__LINE__\n',
  'line-comment-split-open':'x /'+S+'/ c\ny\n__LINE__\n',
  'line-comment-continued':'int a; // c'+S+'int b;\nint c;\n__LINE__\n',
  'line-comment-continued-twice':'int a; // c'+S+'int b;'+S+'int d;\nint c;\n__LINE__\n',
  'line-comment-hides-block':'int a; // c /*\nint b; /* d */ int c;\n__LINE__\n',
  'directive-line-comment-hides-block':'#if 1 // c /*\nint b;\n#endif // e /*\nint c; /* d */ int f;\n__LINE__\n',
  'define-comment-split-close':'#define X 1 /* q *'+S+'/ + 2\nX\n__LINE__\n',
  'define-comment-continued':'#define X 1 /* q'+S+' r */ + 2\nX\n__LINE__\n',
  'define-line-comment-continued':'#define X 1 // q'+S+'+ 2\nX\n__LINE__\n',
  'define-comment-split-open':'#define X 1 /'+S+'* q */ + 2\nX\n__LINE__\n',
  'if-comment-split-close':'#if 1 /* *'+S+'/ && 0\nno\n#else\nyes\n#endif\n__LINE__\n',
  'skipped-comment-split':'#if 0\n/* a *'+S+'/\nno\n#else\nyes\n#endif\n__LINE__\n',
  'prefix-comment-split':'/* a *'+S+'/ #define Q 7\nQ\n__LINE__\n',
  'macro-argument-comment':'#define ID(x) x\nID(1 /* , *'+S+'/ + 2)\n__LINE__\n',
  'crlf-comment-split-close':'/* a *\\\r\n/ int x;\r\n__LINE__\r\n',
  'crlf-line-comment-continued':'int a; // c\\\r\nint b;\r\nint c;\r\n__LINE__\r\n',
}
# A splice whose neighbours would join: identifiers, numbers, multi-byte
# punctuators, digraphs and comment openers.  Still explicitly unsupported.
REJECT=[
  b'int ab'+S.encode()+b'cd;\n', b'x=1'+S.encode()+b'2;\n', b'a+'+S.encode()+b'+b;\n',
  b'p-'+S.encode()+b'>q;\n', b'x='+S.encode()+b'.5;\n', b'int a<'+S.encode()+b':1:>;\n',
b'x='+S.encode()+S.encode()+b'y;\n',
  b'x,y'+S.encode()+b'z;\n', b'#def'+S.encode()+b'ine X 1\n', b'/* x */#'+S.encode()+b' 1 "v.c"\n', b'#line 5 /* unclosed'+S.encode()+b'\n', b'a=b\\\r\nc;\r\n', b'#if 0\nab'+S.encode()+b'cd\n#endif\n',
]


def main():
    inputs=sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))+[ROOT/'010-lib.fth',DRIVER,Path(__file__)]
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    work=Path(tempfile.mkdtemp(prefix='file-splice-',dir=ROOT/'build-out'))
    source=work/'input.c';records=[]
    for name,text in ACCEPT.items():
        source.write_bytes(text.encode())
        actual=run([DRIVER,'-E',source]).stdout
        expected=run(['cc','-E','-P',source]).stdout
        assert module.tokens(actual)==module.tokens(expected),(name,actual,expected)
        records.append({'case':name,'sha256':hashlib.sha256(actual).hexdigest()})
    for data in REJECT:
        source.write_bytes(data);out=work/'previous.i';out.write_bytes(b'previous text\n')
        p=run([DRIVER,'-E',source,'-o',out],status=49)
        assert b'error 49' in p.stderr and out.read_bytes()==b'previous text\n',(data,p.stderr)
    source.write_text('''/*****\\
 * banner *\\
/
#define ADD(a,b) ((a)+(b))
static int table[3]={1,\\
\t2,\\
\t3};
static int line_after = __LINE__;
int main(void){
  int sum=ADD(table[0],\\
\t\ttable[1])+ADD(table[2],\\
\\
 0);
  // a continued comment hides the next line \\
  return 4;
  if(sum!=6) return 1;
  if(line_after!=8) return 2;
  if(__LINE__!=18) return 3;
  return 0;
}
''')
    exe=work/'file-splice';run([DRIVER,source,'-o',exe]);run([exe])
    assert hashes=={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    report={'status':'PASS','source_sha256':hashes,'token_cases':records,'reject49_preserves_output':len(REJECT),'production':'Forth compiler/runtime/linker executes continued initializer and macro arguments with physical __LINE__','oracle':'host CPP token comparison only','scope':'Continuations replaced by their newline at token boundaries; joining splices remain unsupported'}
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: source-text continuations at token boundaries, rejections and Forth execution')
    print(work/'report.json')


if __name__=='__main__':main()
