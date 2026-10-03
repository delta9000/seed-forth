#!/usr/bin/env python3
"""Independent exact-rational binary64 literal review; never parses via float.

The Python side creates test inputs and integer reference encodings only.
Production bytes are decoded/emitted by seed Forth. Exact halfway values and
neighbours expose double rounding, normal/subnormal transitions, and ties.
"""
from pathlib import Path
from fractions import Fraction
import argparse
import hashlib
import json
import random
import re
import shutil
import struct
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]


def rational(token):
    mantissa,*exponent=re.split('[eE]',token)
    parts=mantissa.split('.')
    digits=''.join(parts)
    power=(int(exponent[0]) if exponent else 0)-(len(parts[1]) if len(parts)==2 else 0)
    n=int(digits)
    return Fraction(n*10**max(power,0),10**max(-power,0))


def rounded_integer(n,d):
    q,r=divmod(n,d)
    return q+(2*r>d or (2*r==d and q%2==1))


def expected_bits(number):
    if not number: return 0
    n,d=number.numerator,number.denominator
    e=n.bit_length()-d.bit_length()
    if (n < d<<e) if e>=0 else (n<<-e < d): e-=1
    shift=1074 if e < -1022 else 52-e
    q=rounded_integer(n<<shift,d) if shift>=0 else rounded_integer(n,d<<-shift)
    if e < -1022: return q
    if q==1<<53: q>>=1; e+=1
    if e>1023: raise OverflowError
    return ((e+1023)<<52)+(q-(1<<52))


def from_bits(bits):
    exponent=bits>>52
    significand=bits&((1<<52)-1)
    if exponent: significand|=1<<52
    shift=exponent-1023-52 if exponent else -1074
    return Fraction(significand<<max(shift,0),1<<max(-shift,0))


def decimal(number):
    """Exact decimal spelling of a nonnegative rational with a dyadic divisor."""
    n,d=number.numerator,number.denominator
    power=d.bit_length()-1
    assert d==1<<power
    digits=str(n*5**power)
    if not power: return digits+'.0'
    digits=digits.rjust(power+1,'0')
    return digits[:-power]+'.'+digits[-power:]


def accepted_tokens():
    tokens=['0.0','.0','0.','00.0','0e1000000','0e-1000000','.5','1.','1e3',
        '1E+3','000001.2500','010.0','0.1','1.0000000000000002','1e-324',
        '1e-1000000','2.2250738585072014e-308','1.7976931348623157e308',
        '4.9406564584124654e-324','2.4703282292062327e-324',
        '2.4703282292062328e-324','9007199254740993.0']
    # Adjacent values around minsubnormal, normal/subnormal boundary,
    # powers of two, both midpoint parity choices, and maxfinite.
    anchors=[0,1,2,3,(1<<52)-2,(1<<52)-1,1<<52,(1<<52)+1,
        0x3fefffffffffffff,0x3ff0000000000000,0x3ff0000000000001,
        0x3ff0000000000002,0x4340000000000000,0x7feffffffffffffe]
    for bits in anchors:
        a,b=from_bits(bits),from_bits(bits+1)
        midpoint=(a+b)/2
        tokens.extend([decimal(a),decimal(b),decimal(midpoint)])
        # Changing one terminal decimal place gives exact values straddling
        # the midpoint while staying within the 768 significant-digit bound.
        t=decimal(midpoint)
        places=len(t.partition('.')[2])
        step=Fraction(1,10**places)
        for delta in (-step,step):
            v=midpoint+delta
            if v>=0:
                # Fraction may no longer be dyadic: spell using decimal scale.
                scaled=v*10**places
                assert scaled.denominator==1
                s=str(scaled.numerator).rjust(places+1,'0')
                s=s[:-places]+'.'+s[-places:] if places else s+'.0'
                if len(s.replace('.','').lstrip('0'))<=768: tokens.append(s)
    rng=random.Random(0x53464F525448)
    for _ in range(40):
        digits=str(rng.randrange(1,10**rng.randrange(1,45)))
        exponent=rng.randrange(-355,270)
        tokens.append(digits+'e'+str(exponent))
    tokens += ['.'+'0'*300+'1e301','1'+'0'*767+'e-767','0'*4094+'.0']
    return list(dict.fromkeys(tokens))


def forth_prelude():
    return b'\n'.join((ROOT/name).read_bytes() for name in
        ('010-lib.fth','020-cc-arena.fth'))+b'\nskip-vm-pages\ndefer cc-f64-parse-fwd\n'+(
        ROOT/'128-cc-float-literal.fth').read_bytes()+b'\ncreate review-output [lit] 0 ,\n'


def encoded_token(token,index):
    data=token.encode('ascii')
    return ('create review-token-'+str(index)+'\n'+''.join('[lit] '+str(b)+' c,\n' for b in data)+
        'review-token-'+str(index)+' [lit] '+str(len(data))+' cc-f64-parse\n'
        'review-output ! [lit] 1 review-output [lit] 8 write drop\n').encode()


def compiler_hashes():
    paths=[ROOT/'seed-forth',ROOT/'010-lib.fth',ROOT/'tests/gcc/sysv-object-compile.sh']
    paths += [p for p in sorted(ROOT.glob('[0-9][0-9][0-9]-cc-*.fth'))
              if p.name not in ('120-cc-main.fth','140-cc-link.fth')]
    return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--decoder-only',action='store_true')
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    compiler_snapshot=compiler_hashes()
    object_hash=None
    decoder=ROOT/'128-cc-float-literal.fth'
    decoder_hash=hashlib.sha256(decoder.read_bytes()).hexdigest()
    tokens=accepted_tokens()
    expected=[expected_bits(rational(t)) for t in tokens]
    source=forth_prelude()+b''.join(encoded_token(t,i) for i,t in enumerate(tokens))+b'bye\n'
    result=subprocess.run([ROOT/'seed-forth'],input=source,capture_output=True)
    if result.returncode or result.stderr:
        raise RuntimeError(f'decoder exit {result.returncode}: {result.stderr!r}, {result.stdout[:200]!r}')
    if len(result.stdout)!=8*len(tokens):
        raise RuntimeError(f'Unexpected decoder output length: {len(result.stdout)}')
    actual=struct.unpack('<'+'Q'*len(tokens),result.stdout)
    for t,a,e in zip(tokens,actual,expected):
        if a!=e: raise AssertionError(f'{t}: {a:016x} != {e:016x}')
    print(f'PASS: exact-rational decoder oracle {len(tokens)} decimal spellings')
    rejects={
        'suffix-f':('1.0f','suffix-unsupported'),'suffix-F':('1e0F','suffix-unsupported'),
        'suffix-l':('1.0l','suffix-unsupported'),'suffix-L':('1.L','suffix-unsupported'),
        'hex-lower':('0x1.8p0','hexfloat-unsupported'),
        'hex-upper':('0X1P0','hexfloat-unsupported'),
        'unary-negative':('-1.0','malformed'),'empty':('','malformed'),
        'point-only':('.','malformed'),'no-marker':('123','malformed'),
        'missing-exponent':('1e','malformed'),'missing-signed-exponent':('1e-','malformed'),
        'double-point':('1.2.3','malformed'),'trailing-junk':('1.2abc','malformed'),
        'positive-exponent-bound':('0e1000001','exponent-limit'),
        'negative-exponent-bound':('0e-1000001','exponent-limit'),
        'digit-bound':('1'+'0'*767+'.0','digit-limit'),
        'token-bound':('0'*4095+'.0','token-limit'),
        'obvious-overflow':('1e309','overflow'),
        'round-to-infinity':('1.7976931348623159e308','overflow'),
    }
    for name,(token,reason) in rejects.items():
        result=subprocess.run([ROOT/'seed-forth'],input=forth_prelude()+encoded_token(token,0)+b'bye\n',capture_output=True)
        if result.returncode!=248 or (b'cc-f64-literal: '+reason.encode()) not in result.stderr:
            raise AssertionError((name,result.returncode,result.stdout,result.stderr))
        if result.stdout: raise AssertionError((name,'decoder published a value'))
    print(f'PASS: exact literal grammar/bounds {len(rejects)} explicit decoder rejections')
    integrated=[]
    if not args.decoder_only:
        cc=shutil.which('cc')
        if not cc: raise RuntimeError('Host C compiler needed only for XMM0 output oracle')
        with tempfile.TemporaryDirectory(prefix='review-floating-literal.') as temp:
            work=Path(temp)
            production=work/'literals.c'
            expressions=list(tokens)
            source_expected=list(expected)
            for t in ('0.0','1.0','1e-1000000','4.9406564584124654e-324','1.7976931348623157e308'):
                expressions.append('-'+t)
                source_expected.append(expected_bits(rational(t))|(1<<63))
            for t in ('0.0','1e3'):
                expressions.append('+'+t)
                source_expected.append(expected_bits(rational(t)))
            production.write_text(''.join(f'double review_literal_{i}(void){{return {t};}}\n' for i,t in enumerate(expressions)))
            obj=work/'literals.o'
            subprocess.run([ROOT/'tests/gcc/sysv-object-compile.sh',production,obj],check=True)
            object_hash=hashlib.sha256(obj.read_bytes()).hexdigest()
            oracle=work/'oracle.c'
            oracle.write_text('#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n'+
                ''.join(f'extern double review_literal_{i}(void);\n' for i in range(len(expressions)))+
                'int main(void){ double (*f[])(void)={'+','.join(f'review_literal_{i}' for i in range(len(expressions)))+'};\n'+
                'uint64_t expected[]={'+','.join(f'UINT64_C(0x{v:x})' for v in source_expected)+'};\n'+
                f'for(unsigned i=0;i<{len(expressions)};i++){{double d=f[i]();uint64_t u;memcpy(&u,&d,8);'+
                'if(u!=expected[i]){fprintf(stderr,"literal %u: %llx != %llx\\n",i,(unsigned long long)u,(unsigned long long)expected[i]);return 1;}}return 0;}\n')
            for opt in ('-O0','-O2'):
                binary=work/('oracle'+opt[1:])
                subprocess.run([cc,opt,'-std=c99','-Wall','-Wextra','-Werror','-fno-pie','-no-pie',
                    '-Wl,-z,noexecstack',oracle,obj,'-o',binary],check=True)
                subprocess.run([binary],check=True)
                integrated.append(opt)
                print(f'PASS: source literals -> Forth object -> host {opt} XMM0 oracle {len(expressions)} values')
            # Markerless/sign-only strings are decoder-only: in actual C the
            # lexer recognizes integer literals and the parser owns unary sign.
            for name in ('suffix-f','suffix-F','suffix-l','suffix-L','hex-lower','hex-upper',
                         'positive-exponent-bound','negative-exponent-bound','digit-bound',
                         'token-bound','obvious-overflow','round-to-infinity'):
                token,reason=rejects[name]
                production.write_text(f'double f(void){{return {token};}}\n')
                rejected=work/(name+'.o')
                result=subprocess.run([ROOT/'tests/gcc/sysv-object-compile.sh',production,rejected],capture_output=True)
                if result.returncode!=248 or (b'cc-f64-literal: '+reason.encode()) not in result.stderr:
                    raise AssertionError((name,result.returncode,result.stdout,result.stderr))
                if rejected.exists(): raise AssertionError((name,'rejected source object published'))
            print('PASS: unsupported source literal spellings fail explicitly before object publication')
    if hashlib.sha256(decoder.read_bytes()).hexdigest()!=decoder_hash:
        raise RuntimeError('Decoder changed during review; rerun after source freeze')
    if compiler_hashes()!=compiler_snapshot:
        raise RuntimeError('Compiler changed during review; rerun after source freeze')
    report={'compiler_sha256':compiler_snapshot,'source_object_sha256':object_hash,'decoder_sha256':decoder_hash,'accepted':len(tokens),'decoder_rejections':len(rejects),'source_rejections':12 if integrated else 0,
            'integrated_host_optimizations':integrated,'source_values':len(tokens)+7 if integrated else 0,'reference':'Python exact integer rational rounding; no float parser'}
    if args.report: args.report.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')

if __name__=='__main__': main()
