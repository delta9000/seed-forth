#!/usr/bin/env python3
"""Unavailable macro tokens survive rescan; host preprocessing is an oracle."""
from pathlib import Path
import importlib.util,json,subprocess,resource,os,signal,tempfile,hashlib
ROOT=Path(__file__).resolve().parents[2];WORK=Path(tempfile.mkdtemp(prefix='macro-suppression-',dir=ROOT/'build-out'));DRIVER=ROOT/'tools/gcc-direct-cc.py'
def tokens(data):
    """Maximal-munch preprocessing tokens; no punctuator/escape normalization."""
    out=[];i=0;n=len(data)
    punct=sorted([b'%:%:',b'>>=',b'<<=',b'...',b'->',b'++',b'--',b'<<',b'>>',b'<=',b'>=',b'==',b'!=',b'&&',b'||',b'*=',b'/=',b'%=',b'+=',b'-=',b'&=',b'^=',b'|=',b'##',b'<:',b':>',b'<%',b'%>',b'%:'],key=len,reverse=True)
    def alpha(c):return 65<=c<=90 or 97<=c<=122 or c==95
    def digit(c):return 48<=c<=57
    while i<n:
        if data[i] in b' \t\n\r\v\f':i+=1;continue
        if data.startswith(b'/*',i):
            end=data.find(b'*/',i+2);assert end>=0; i=end+2;continue
        if data.startswith(b'//',i):
            end=data.find(b'\n',i+2);i=n if end<0 else end+1;continue
        start=i;q=i
        for prefix in (b'u8',b'L',b'u',b'U'):
            if data.startswith(prefix,i) and i+len(prefix)<n and data[i+len(prefix)] in (34,39):q=i+len(prefix);break
        if data[q] in (34,39):
            quote=data[q];i=q+1
            while i<n:
                if data[i]==92:i+=2
                elif data[i]==quote:i+=1;break
                else:i+=1
            else:raise AssertionError('unterminated literal')
        elif alpha(data[i]):
            i+=1
            while i<n and (alpha(data[i]) or digit(data[i])):i+=1
        elif digit(data[i]) or (data[i]==46 and i+1<n and digit(data[i+1])):
            i+=1
            while i<n:
                if alpha(data[i]) or digit(data[i]) or data[i]==46:i+=1
                elif data[i] in (43,45) and data[i-1] in b'eEpP':i+=1
                else:break
        else:
            found=next((p for p in punct if data.startswith(p,i)),None)
            if found:i+=len(found)
            else:
                assert data[i] in b'{}[]#();:,.?~!%^&*+-=/|<>',('unsupported byte',data[i],i)
                i+=1
        out.append(data[start:i])
    return out
# These must differ: whitespace separates preprocessing tokens.
for a,b in [(b'++',b'+ +'),(b'>>',b'> >'),(b'>=',b'> ='),(b'##',b'# #'),(b'1e+2',b'1e + 2'),(b'"ab"',b'"a" "b"')]:
    assert tokens(a)!=tokens(b),(a,b)
assert tokens(b'x /* gap */ + y')==tokens(b'x+y')
records=[]
def run(cmd):
 def cap():resource.setrlimit(resource.RLIMIT_AS,(1024**3,1024**3));resource.setrlimit(resource.RLIMIT_CPU,(180,180))
 p=subprocess.Popen(list(map(str,cmd)),stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True,preexec_fn=cap)
 try:o,e=p.communicate(timeout=240)
 except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.communicate();raise
 return p.returncode,o,e
cases={
'self-object':'#define a a\na a\n',
'self-member':'#define f hooks.f\n#define I(x) x\nI(f(42))\n',
'repeated-parameter':'#define f hooks.f\n#define I(x) x+x\nI(f(42))\n',
'deep-arguments':'#define f hooks.f\n#define I(x) x\nI(I(I(I(f(42)))))\n',
'mutual-objects':'#define A B\n#define B A\n#define I(x) x\nI(A) I(B) A B\n',
'mutual-arithmetic':'#define x (4+y)\n#define y (2*x)\n#define I(a) a\nx y I(x) I(y)\n',
'self-function':'#define f(x) f(x)\n#define I(x) x\nf(1) I(f(2)) I(I(f(3)))\n',
'self-function-tail':'#define f() f\nf()()\n',
'function-alias-tail':'#define f(x) x\n#define g f\nf(g)(2) g(g)(3)\n',
'mixed-recursion':'#define A(x) B(x)\n#define B(x) A(x)\n#define I(x) x\nA(1) B(2) I(A(3)) I(B(4))\n',
'argument-not-permanent':'#define f(x) x\nf(f(1)) f(f(f(2)))\n',
'function-name-not-call':'#define f(x) x\n#define I(x) x\nI(f)(2)\n',
'self-two-args':'#define f(x,y) f(y,x)\n#define I(x) x\nI(f(1,2))\n',
'bluepaint-cross-token':'#define f(x) x x\nf(f)(2)\n',
'nested-delayed':'#define f(x) x\n#define g(x) f(x)\nf(g)(1)\n',
'stringify-direct':'#define f hooks.f\n#define S(x) #x\nS(f)\n',
'stringify-expanded':'#define f hooks.f\n#define S(x) #x\n#define E(x) S(x)\nE(f)\n',
'paste-ordinary':'#define JOIN(a,b) a##b\n#define AB 42\nJOIN(A,B)\n',
'paste-raw-self':'#define A A\n#define JOIN(a,b) a##b\n#define AB 42\nJOIN(A,B)\n',
'paste-then-suppress':'#define JOIN(a,b) a##b\n#define AB AB\n#define I(x) x\nI(JOIN(A,B))\n',
'redefinition':'#define A A\n#define I(x) x\nI(A)\n#undef A\n#define A 42\nI(A)\n',
'defined-still-sees-macro':'#define A A\n#define I(x) x\n#if defined(A)\nI(A)\n#endif\n',
'line-counts':'#line 61 "logical.c"\n#define f hooks.f\n#define I(x) x\nI(f(__LINE__)) __LINE__ __FILE__\n',
'newlines':'#define f hooks.f\n#define I(x) x\nI(\n f(1)\n) __LINE__\n',
'unrelated-next-token':'#define f hooks.f\n#define I(x) x\nI(f) f\n',
'late-argument-macro':'#define x x\n#define f(x) x\n#define g f\ng(g)(x)\n',
'operator-spacing':'#define f hooks.f\n#define I(x) x\n-I(f) + +I(f)\n',
'quoted-not-expanded':'#define f hooks.f\n#define I(x) x\nI("f") I(\'f\') I(f)\n',
}
for n in range(1,13):
 defs=''.join(f'#define M{i} M{(i+1)%n}\n' for i in range(n));cases[f'cycle-{n}']=defs+'#define I(x) x\nI(I(M0)) M0\n'
for name,source in cases.items():
 p=WORK/(name+'.c');p.write_text(source);c,a,e=run(['python3',DRIVER,'-E',p]);hc,h,he=run(['gcc','-std=c90','-pedantic-errors','-E','-P',p]);(WORK/(name+'.i')).write_bytes(a);(WORK/(name+'.host.i')).write_bytes(h);(WORK/(name+'.stderr')).write_bytes(e);assert (c,hc,e,he)==(0,0,b'',b''),(name,c,hc,e,he)
 assert tokens(a)==tokens(h),(name,a,h)
 records.append({'case':name,'status':'PASS','source_sha256':hashlib.sha256(source.encode()).hexdigest(),'actual_sha256':hashlib.sha256(a).hexdigest(),'host_sha256':hashlib.sha256(h).hexdigest()});(WORK/'report.json').write_text(json.dumps({'status':'in-progress','cases':records},indent=2)+'\n');print('PASS',name,flush=True)
# Unavailable pasted operands need a token-level placemarker model; fail closed.
for suffix in ['B','']:
 for present in [False,True]:
  name='unavailable-paste-'+repr(suffix)+'-'+str(present);p=WORK/(name+'.c');p.write_text('#define A A\n#define P(x,y) x##y\n#define I(x) P(x,'+suffix+')\nI(A)\n');out=WORK/(name+'.i')
  if present:out.write_bytes(b'previous output\n')
  c,a,e=run(['python3',DRIVER,'-E',p,'-o',out]);assert c==47 and b'error 47' in e,(name,c,a,e);assert out.exists()==present
  if present:assert out.read_bytes()==b'previous output\n'
  records.append({'case':name,'status':'checked unsupported','diagnostic':47})
(WORK/'report.json').write_text(json.dumps({'status':'PASS','cases':records,'compiler_identity':run(['python3',DRIVER,'--print-source-hash'])[1].decode().strip()},indent=2)+'\n');print('PASS',len(records),'cases',WORK,flush=True)
