#!/usr/bin/env python3
"""Independent deterministic SysV bitfield ABI and expression regression review.

Host GCC is used only as an independent interoperability oracle. Production
compilation, object emission and the optional consumer link run through Forth.
Generated C inputs are retained with hashes to make the review reproducible.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args, expected=0):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=120)
    if result.returncode != expected:
        raise AssertionError(f'{args}: wanted {expected}, got {result.returncode}\n{result.stdout}{result.stderr}')
    return result


def fixture(work):
    layouts = []
    for ty in ('unsigned', 'signed', 'unsigned long', 'long'):
        for width in (1, 2, 7, 8, 9, 16, 30, 31, 32):
            # All assigned values are representable: signed overflow is not a
            # positive test. Unsigned wrap is checked separately below.
            signed = ty in ('signed', 'long')
            value = f'(v % {1 << (width - 1 if signed else width)}L)'
            second = f'(-{value}-1)' if signed else value
            decl = f'char head; {ty} a:{width}; unsigned guard:1; {ty} b:{width}; unsigned:0; char tail;'
            layouts.append((decl, f'p->head=37;p->a={value};p->guard=v&1;p->b={second};p->tail=81;'))
    layouts += [
        ('char head; long a:64; unsigned long b:64; char tail;', 'p->head=37;p->a=-v;p->b=v;p->tail=81;'),
        ('char head; unsigned a:7; unsigned long b:32; unsigned c:2; long d:31; char tail;', 'p->head=37;p->a=v&127;p->b=v;p->c=v&3;p->d=-(v%1073741824L);p->tail=81;'),
        ('char head; unsigned:0; unsigned:3; unsigned a:9; unsigned long:0; signed b:16; char tail;', 'p->head=37;p->a=v&511;p->b=-(v%32768);p->tail=81;'),
        ('char head; struct {unsigned a:9; signed b:7;}; union {unsigned c:30; struct {unsigned d:8; unsigned e:16;};}; char tail;', 'p->head=37;p->a=v&511;p->b=-(v%64);p->c=v;p->d=v&255;p->e=v&65535;p->tail=81;'),
        ('char head; unsigned a:31; unsigned:2; unsigned b:30; char tail;', 'p->head=37;p->a=v;p->b=v;p->tail=81;'),
        ('char head; unsigned:3; char tail;', 'p->head=37;p->tail=81;'),
        ('char head; unsigned long:0; char tail;', 'p->head=37;p->tail=81;'),
    ]
    header = []
    production = ['#include "review-bitfield-layout.h"']
    oracle = ['#include <stdio.h>', '#include <string.h>', '#include "review-bitfield-layout.h"', 'int main(void){int i;long v;']
    for i, (decl, action) in enumerate(layouts):
        header += [f'struct R{i} {{{decl}}};', f'void review_set_{i}(struct R{i}*,long);', f'long review_size_{i}(void);', f'long review_tail_{i}(struct R{i}*);']
        production += [f'void review_set_{i}(struct R{i} *p,long v){{{action}}}', f'long review_size_{i}(void){{return sizeof(struct R{i});}}', f'long review_tail_{i}(struct R{i} *p){{return (char*)&p->tail-(char*)p;}}']
        oracle += [f'{{struct R{i} h,f;struct R{i} *p=&h;if(review_size_{i}()!=sizeof h||review_tail_{i}(&f)!=(char*)&h.tail-(char*)&h){{printf("layout {i} size %ld/%zu\\n",review_size_{i}(),sizeof h);return 1;}}',
                   f'for(i=0;i<5;i++){{v=i==0?0:i==1?1:i==2?1431655765L:i==3?2147483647L:4294967295L;memset(&h,i*51,sizeof h);memcpy(&f,&h,sizeof h);{action}review_set_{i}(&f,v);if(memcmp(&h,&f,sizeof h)){{printf("bytes {i} pattern %d\\n",i);return 2;}}}}}}']
    header += ['struct E {unsigned a:3;signed b:7;unsigned c:31;unsigned d:32;long e:32;long f:64;unsigned long g:64;int normal;};', 'void review_expr(struct E*,long*,double*);', 'void review_volatile(volatile struct E*);',
               'union U {unsigned a:9;signed b:9;unsigned long c:32;unsigned char bytes[16];};', 'void review_union(union U*,long*);', 'int review_initializers(void);', 'int review_side_effects(struct E*);']
    actions = [
        'p->a=7', 'p->b=-31', 'p->c=2147483647U', 'p->d=4294967295U', 'p->e=-123456', 'p->f=-9000000000L', 'p->g=18446744073709551615UL', 'p->normal=73',
        'o[0]=p->a++', 'o[1]=p->a', 'o[2]=++p->a', 'o[3]=p->b--', 'o[4]=--p->b',
        'o[5]=(p->a+=5)', 'o[6]=(p->a*=2)', 'o[7]=(p->b/=3)', 'o[8]=(p->b%=4)',
        'o[9]=(p->d+=1U)', 'o[10]=(p->c< -1)', 'o[11]=(-1<p->c)', 'o[12]=p->a-10',
        'o[13]=p->a*-2', 'o[14]=p->b>>2', 'o[15]=(p->d< -1)', 'o[16]=(p->e< -1)',
        'o[17]=sizeof(+p->a)', 'o[18]=sizeof(+p->d)', 'o[19]=sizeof(+p->e)', 'o[20]=sizeof(+p->g)',
        'o[21]=(p->b=-17)', 'o[22]=(p->a=p->normal=6)', 'o[23]=p->normal',
        'o[24]=(p->b+=p->a)', 'o[25]=(p->a=p->a==6?3:4)', 'o[26]=p->a?sizeof p->normal:99',
        'o[27]=(p->a<<=1)', 'o[28]=(p->a>>=2)', 'o[29]=(p->a|=4)', 'o[30]=(p->a^=3)', 'o[31]=(p->a&=6)',
        'p->a=*d', 'p->b=-*d', 'o[32]=p->a', 'o[33]=p->b', '*d=p->b',
        'o[34]=(p->a+=1.75)', 'o[35]=(p->b*=0.5)', 'o[36]=p->normal+4',
        'o[37]=(p->g+=1UL)', 'o[38]=p->f+1', 'o[39]=(p->d=4294967295U)',
        'o[40]=(p->d>p->b)', 'o[41]=(-1<p->d)', 'o[42]=(p->a&&p->b)', 'o[43]=(p->a||p->normal)',
        'o[44]=(p->a=p->b==-2?7:5)', 'o[45]=p->a+sizeof(p->normal)',
    ]
    body = ';'.join(actions) + ';'
    production += ['void review_expr(struct E *p,long *o,double *d){'+body+'}',
                   'void review_volatile(volatile struct E *p){p->a=3;p->b+=2;p->normal=91;}',
                   'void review_union(union U *p,long *o){p->c=305419896U;o[0]=p->a;o[1]=p->b;p->b=-19;o[2]=p->c;o[3]=p->b;p->a+=3;o[4]=p->a;o[5]=p->b;}',
                   'struct I {unsigned:1;unsigned a:3;signed b:7;unsigned:0;unsigned c:16;};',
                   'struct I review_static[2]={{5,-24,17},{7,17,65535}};',
                   'int review_initializers(void){struct I local[2]={{3,-61,32768},{2,63,2}};return review_static[0].a==5&&review_static[0].b==-24&&review_static[0].c==17&&review_static[1].a==7&&review_static[1].b==17&&review_static[1].c==65535&&local[0].a==3&&local[0].b==-61&&local[0].c==32768&&local[1].a==2&&local[1].b==63&&local[1].c==2;}',
                   'int review_side_effects(struct E *p){int i;int x;int *q;i=0;x=p[i++].a++;if(i!=1||x!=7||p[0].a!=0)return 0;i=0;x=++p[i++].a;if(i!=1||x!=1||p[0].a!=1)return 0;i=0;x=(p[i++].a+=5);if(i!=1||x!=6||p[0].a!=6)return 0;q=&p[0].normal;*q=91;return *q==91&&sizeof(p[0].a+0)==sizeof(int);}'
                   ]
    oracle += ['{struct E h,f;long expected[46],actual[46];double dh=6.75,df=6.75;struct E *p=&h;long *o=expected;double *d=&dh;memset(&h,0xA5,sizeof h);memcpy(&f,&h,sizeof h);'+body+'review_expr(&f,actual,&df);for(i=0;i<46;i++)if(expected[i]!=actual[i]){printf("expr %d: %ld/%ld\\n",i,actual[i],expected[i]);return 3;}if(memcmp(&h,&f,sizeof h)||dh!=df){puts("expression state");return 4;}}',
               '{struct E h,f;memset(&h,0,sizeof h);memcpy(&f,&h,sizeof h);h.a=3;h.b+=2;h.normal=91;review_volatile(&f);if(memcmp(&h,&f,sizeof h)){puts("volatile state");return 5;}}',
               '{union U h,f;long expected[6],actual[6];memset(&h,0xA5,sizeof h);memcpy(&f,&h,sizeof h);h.c=305419896U;expected[0]=h.a;expected[1]=h.b;h.b=-19;expected[2]=h.c;expected[3]=h.b;h.a+=3;expected[4]=h.a;expected[5]=h.b;review_union(&f,actual);if(memcmp(expected,actual,sizeof actual)||memcmp(&h,&f,sizeof h)){puts("union overlap");return 6;}}',
               '{struct E e;memset(&e,0,sizeof e);e.a=7;if(!review_initializers()||!review_side_effects(&e)){puts("initializers or side effects");return 7;}}',
               f'puts("PASS: {len(layouts)} deterministic ABI layouts, 215 object representations and 46 expression results");return 0;}}']
    for name, content in [('review-bitfield-layout.h',header),('review-bitfield-production.c',production),('review-bitfield-oracle.c',oracle)]:
        (work/name).write_text('\n'.join(content)+'\n')
    return len(layouts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler-root',type=Path,default=ROOT)
    parser.add_argument('--work',type=Path)
    parser.add_argument('--report',type=Path)
    parser.add_argument('--source-root',type=Path,default=ROOT/'build-out/direct-gcc-inputs/gcc-source')
    args=parser.parse_args()
    compiler=args.compiler_root.resolve()
    work=(args.work or Path(tempfile.mkdtemp(prefix='review-bitfield-',dir=ROOT/'build-out'))).resolve()
    work.mkdir(parents=True,exist_ok=True)
    paths=[compiler/'seed-forth',compiler/'010-lib.fth',compiler/'tools/gcc-direct-cc.py',*sorted(compiler.glob('[0-9][0-9][0-9]-cc-*.fth'))]
    hashes={str(p.relative_to(compiler)):sha(p) for p in paths}
    count=fixture(work)
    cc=compiler/'tools/gcc-direct-cc.py'
    obj=work/'review-bitfield-production.o'
    run([cc,'-c',work/'review-bitfield-production.c','-o',obj])
    host=shutil.which('gcc')
    assert host,'GCC is required only as an independent oracle'
    outcomes=[]
    for opt in ('-O0','-O2'):
        binary=work/('review-bitfield-oracle'+opt)
        run([host,opt,'-std=gnu11','-fno-pie','-no-pie','-Wl,-z,noexecstack',work/'review-bitfield-oracle.c',obj,'-o',binary])
        result=run([binary])
        print(opt,result.stdout.strip())
        outcomes.append({'optimization':opt,'stdout':result.stdout,'executable_sha256':sha(binary)})
    rejects={
        'parenthesized-address':'struct X {unsigned x:7;};unsigned *f(struct X *p){return &(p->x);}',
        'nested-sizeof':'struct X {unsigned x:7;};int f(struct X *p){return sizeof((p->x));}',
        'typedef-enum':'typedef enum {A,B} E;struct X {E x:2;};',
        'long-33':'struct X {long x:33;};',
        'ulong-63':'struct X {unsigned long x:63;};',
        'long-65':'struct X {long x:65;};',
        'named-zero':'struct X {unsigned x:0;};',
        'negative-width':'struct X {unsigned x:-1;};',
        'char-bitfield':'struct X {char x:3;};',
        'short-bitfield':'struct X {short x:3;};',
        'double-bitfield':'struct X {double x:3;};',
        'pointer-bitfield':'struct X {unsigned *x:3;};',
        'array-bitfield':'struct X {unsigned x[1]:3;};',
        'static-field-address':'struct X {unsigned x:3;};struct X g;unsigned *p=&g.x;',
    }
    rejected=[]
    for name,source in rejects.items():
        src=work/('review-bitfield-reject-'+name+'.c');src.write_text(source+'\n')
        out=work/('review-bitfield-reject-'+name+'.o')
        out.unlink(missing_ok=True)
        for existing in (False,True):
            if existing: out.write_bytes(b'preserve-review-output\0\xff')
            result=run([cc,'-c',src,'-o',out],248)
            assert 'bitfield:' in result.stderr,(name,result.stderr)
            assert (out.read_bytes()==b'preserve-review-output\0\xff') if existing else not out.exists(),name
        rejected.append(name)
    print(f'PASS: {len(rejected)} rejected forms preserve absent and existing outputs')
    original_header=args.source_root.resolve()/'include/obstack.h'
    assert sha(original_header)=='099f6cf0cb38cadf0040b4c0e235026401004104e96349d9211daaa6e3a38aa4','Original GCC obstack header changed'
    consumer=ROOT/'tests/gcc/review-bitfield-obstack.c'
    consumer_obj=work/'review-bitfield-obstack.o'
    include='-I'+str(original_header.parent)
    run([cc,'-c',include,consumer,'-o',consumer_obj])
    consumer_runs=[]
    for opt in ('-O0','-O2'):
        binary=work/('review-bitfield-obstack'+opt)
        run([host,opt,'-DREVIEW_OBSTACK_MAIN','-DREVIEW_OBSTACK_EXTERNAL',include,'-fno-pie','-no-pie','-Wl,-z,noexecstack',consumer,consumer_obj,'-o',binary])
        result=run([binary])
        consumer_runs.append({'mode':'host-oracle'+opt,'stdout':result.stdout,'executable_sha256':sha(binary)})
    binary=work/'review-bitfield-obstack-forth'
    run([cc,'-DREVIEW_OBSTACK_MAIN',include,consumer,'-o',binary])
    result=run([binary])
    consumer_runs.append({'mode':'forth-only','stdout':result.stdout,'executable_sha256':sha(binary)})
    print(result.stdout.strip()+'; Forth-only and host O0/O2')
    disassembly=run(['objdump','-dr',obj]).stdout
    volatile=disassembly.split('<review_volatile>:',1)[1].split('\n\n',1)[0]
    # One preserving read per store, plus a separate compound operand read.
    assert len(re.findall(r'mov\s+\(%rcx\),%eax',volatile))==2,volatile
    assert len(re.findall(r'mov\s+%eax,\(%rcx\)',volatile))==2,volatile
    assert len(re.findall(r'movslq\s+\(%rdi\),%rdi',volatile))==1,volatile
    assert 'lock ' not in volatile
    (work/'review-bitfield-volatile-disassembly.txt').write_text(volatile+'\n')
    print('PASS: volatile unit RMW contract: two preserving loads/stores, one compound operand load')
    assert hashes=={str(p.relative_to(compiler)):sha(p) for p in paths},'Compiler changed during review'
    report={'compiler_sha256':hashes,'fixture_sha256':{p.name:sha(p) for p in work.glob('review-bitfield-*') if p.suffix in ('.c','.h')},'review_source_sha256':{Path(__file__).name:sha(Path(__file__)),consumer.name:sha(consumer)},'production_object_sha256':sha(obj),'host_gcc':run([host,'--version']).stdout.splitlines()[0],'layouts':count,'host_oracles':outcomes,'rejected':rejected,'work':str(work),'obstack':{'original_header_sha256':sha(original_header),'production_object_sha256':sha(consumer_obj),'runs':consumer_runs},'volatile_contract':{'unit_reads':3,'unit_writes':2,'atomic':False,'disassembly_sha256':sha(work/'review-bitfield-volatile-disassembly.txt')},'limitations':['Deterministic object representation comparison is a measured GCC ABI test, not a portable C padding-byte guarantee.','No atomicity or signed-overflow behavior is claimed.','Intermediate long bit widths 33 through 63 deliberately reject.','Original obstack header macros are executed; this is not a claim that the full obstack.c translation unit passes.']}
    output=args.report or work/'review-bitfield-results.json'
    output.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(output)


if __name__=='__main__':
    main()
