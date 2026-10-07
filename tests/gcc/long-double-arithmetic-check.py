#!/usr/bin/env python3
"""Compare x87 scalar computations and exact constants with host GCC."""
from pathlib import Path
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(args):
    p = subprocess.run([str(a) for a in args], capture_output=True, timeout=300)
    assert p.returncode == 0, (args, p.returncode, p.stdout, p.stderr)
    return p.stdout


def main():
    rng = random.Random(807116)
    values = ['0x0p0', '-0x0p0', '0x1p-16445', '-0x1p-16445',
              '0x7fffffffffffffffp-16445', '0x1p-16382',
              '0x1.fffffffffffffffep16383', '-0x1.fffffffffffffffep16383',
              '1', '-1', '1.5', '-2.75', 'inf', '-inf', 'nan']
    for _ in range(256):
        exponent = rng.randint(-16445, 16383)
        significand = rng.getrandbits(63)
        values.append(f'{rng.choice(["", "-"])}0x1.{significand << 1:016x}p{exponent}')
    constants = ['0.0L', '-0.0L', '0x0p0L', '-0x0p0L', '0x0p1000000L', '1.0L', '-1.0L',
                 '0x1p-16445L', '0x1p-16446L', '0x1.0000000000000002p-16446L',
                 '0x1.fffffffffffffffcp-16383L', '0x1.fffffffffffffffep16383L',
                 '1e4932L', '1e-4950L',
                 '1.0000000000000000000542101086242752217003726400434970855712890625L',
                 '1.0000000000000000001626303258728256651011179201304912567138671875L',
                 '(1.0L+0x1p-63L)', '(1.0L-0x1p-63L)',
                 '(0x1p10000L+0x1p-10000L)', '(0x1p-10000L/3.0L)',
                 '(0x1p10000L*0x1p-10000L)', '(long double)18446744073709551615UL',
                 '(unsigned long)(0x1p64L-1.0L)', '(long)(-3.75L)',
                 '(0.0L == -0.0L)', '(1.0L < 2.0L)', '(1.0L > -2.0L)',
                 '(1?1.0L:2.0)', '(0?2.0:1.0L)',
                 '1e5000L', '-1e5000L', '(1e4932L*10.0L)',
                 '(1.0L/0.0L)', '(-1.0L/0.0L)', '(0.0L/0.0L)',
                 '(1e5000L-1e5000L)', '(1e5000L*0.0L)', '(1.0L/1e5000L)',
                 '((0.0L/0.0L)==(0.0L/0.0L))', '((0.0L/0.0L)!=(0.0L/0.0L))',
                 '(double)(1.0L/0.0L)', '(float)(0.0L/0.0L)', '(-0.0L/0.0L)', '(0.0L/-0.0L)',
                 '(-(0.0L/0.0L)+1.0L)', '(1.0L-(-(0.0L/0.0L)))',
                 '(-(0.0L/0.0L)*-1.0L)', '(-1e5000L/1e5000L)',
                 '(-1e5000L*0.0L)', '(-1e5000L+1e5000L)']
    for _ in range(24):
        e = rng.randint(-16000, 16000)
        m = rng.getrandbits(63) << 1
        v = f'0x1.{m:016x}p{e}L'
        constants.extend([v, f'({v}/3.0L)', f'({v}*0.5L)', f'({v}-{v})'])
    source = r'''
#include <stdio.h>
#include <stdlib.h>
static const char *input[] = { INPUT };
static long double constants[] = { CONSTANTS };
static long double global_update=3.5L;
static long double id(long double x) { return x; }
static long double mix(long a, long double x, double d, long double y) { return x+y+a+d; }
static void compute(long double x, long double y) {
 long double a=x,b=x,c=x,d=x,p=x,q=x,r=x,s=x;
 a+=y;b-=y;c*=y;d/=y;
 printf("%La %La %La %La %La %La %La %La %La\n",x+y,x-y,x*y,x/y,-x,a,b,c,d);
 printf("%d %d %d %d %d %d %d %d %d %d %d\n",x==y,x!=y,x<y,x<=y,x>y,x>=y,!x,!!x,x&&y,x||y,(_Bool)x);
 printf("%La ",p++); printf("%La ",p); printf("%La ",q--); printf("%La ",q);
 printf("%La %La\n",++r,--s);
 printf("%a %a %La %La\n",(double)(float)x,(double)x,(long double)(float)x,(long double)(double)x);
 printf("%La %La %La\n",id(x),x?x:y,1?x:1.0);
 if(x) printf("T "); else printf("F ");
 while(x) { printf("W ");break; } printf("\n");
}
static void updates(void) {
 struct S { long double member; } s={7.5L};
 long double a[2]={2.5L,4.5L};long double *p=a;int i=0,n=0;
 printf("%La ",global_update++); printf("%La ",global_update);
 printf("%La ",a[i++]++);printf("%d %La ",i,a[0]);
 printf("%La ",++*p);printf("%La ",s.member--);printf("%La ",s.member);
 a[i-1]+=2; s.member/=3;printf("%La %La\n",a[0],s.member);
 global_update=3.0L;while(global_update) {global_update--;n++;}printf("%d %d\n",n,!global_update);
}
static void integers(void) {
 static long signed_values[]={0,1,-1,127,-128,255,256,32767,-32768,65535,2147483647,-2147483647-1,4294967295L,9223372036854775807L,(-9223372036854775807L-1)};
 static unsigned long unsigned_values[]={0UL,1UL,4294967295UL,9223372036854775807UL,9223372036854775808UL,9223372036854775809UL,18446744073709551614UL,18446744073709551615UL};
 int i; long v; unsigned long u;long double x;
 for(i=0;i<sizeof(signed_values)/sizeof(signed_values[0]);i++) {
  v=signed_values[i];x=(long double)v;
  printf("%La %ld %lld\n",x,(long)x,(long long)x);
  printf("%La %La %La %La %La %La %La\n",(long double)(char)v,(long double)(signed char)v,(long double)(unsigned char)v,(long double)(short)v,(long double)(unsigned short)v,(long double)(int)v,(long double)(unsigned int)v);
  printf("%La %La %La\n",(long double)(long long)v,(long double)(unsigned long long)v,(long double)(_Bool)v);
 }
 for(i=0;i<sizeof(unsigned_values)/sizeof(unsigned_values[0]);i++) {
  u=unsigned_values[i];x=u; printf("%La %lu %llu\n",x,(unsigned long)x,(unsigned long long)x);
 }
 // Scalar initializer hooks must convert x87 sources while ordinary integer
 // stores keep the legacy byte sequence pinned by arena-capacity-check.py.
 x=-127.75L;
 {
  signed char c=x;short h=x;int i=x;long l=x;long long ll=x;
  float f=x;double d=x;_Bool b=x;
  printf("%d %d %d %ld %lld %a %a %d\n",c,h,i,l,ll,(double)f,d,b);
  {
   struct I { signed int c:8; _Bool b; double d; float f; long l; } v={x,x,x,x,x};
   union U { signed int c:8; } u={x};
   double a[1]={x};
   printf("%d %d %a %a %ld %d %a\n",v.c,v.b,v.d,(double)v.f,v.l,u.c,a[0]);
  }
 }
 x=255.75L;
 {
  unsigned char c=x;unsigned short h=x;unsigned int i=x;
  unsigned long l=x;unsigned long long ll=x;
  printf("%u %u %u %lu %llu\n",c,h,i,l,ll);
 }
 x=0.0L; { _Bool b=x;printf("%d\n",b); }
 x=-127.75L; printf("%d %d %d %ld %lld\n",(char)x,(short)x,(int)x,(long)x,(long long)x);
 x=255.75L;printf("%u %u %u %lu %llu\n",(unsigned char)x,(unsigned short)x,(unsigned int)x,(unsigned long)x,(unsigned long long)x);
 x=4294967295.75L;printf("%u %lu\n",(unsigned int)x,(unsigned long)x);
 x=9223372036854775807.5L;printf("%ld %lu\n",(long)x,(unsigned long)x);
 x=-9223372036854775808.0L;printf("%ld\n",(long)x);
 printf("%La\n",mix(3,2.0,1.5,4));
}
int main(void) {
 int i;long double x,y;
 for(i=0;i<sizeof(constants)/sizeof(constants[0]);i++)printf("C %La\n",constants[i]);
 integers();updates();
 for(i=0;i<sizeof(input)/sizeof(input[0]);i++) {
  x=strtold(input[i],0);y=strtold(input[(i*37+3)%(sizeof(input)/sizeof(input[0]))],0);
  compute(x,y);
 }
 return 0;
}
'''.replace('INPUT', ','.join('"'+v+'"' for v in values)).replace('CONSTANTS', ','.join(constants))
    with tempfile.TemporaryDirectory(prefix='long-double-arithmetic-', dir=ROOT / 'build-out') as tmp:
        work = Path(tmp)
        c = work / 'check.c'
        c.write_text(source)
        run(['python3', ROOT / 'tools/gcc-direct-cc.py', '-static', c, '-o', work / 'seed'])
        run(['gcc', '-std=gnu99', '-O0', '-static', '-fno-pie', '-no-pie', c, '-o', work / 'gcc'])
        actual = run([work / 'seed'])
        expected = run([work / 'gcc'])
        if actual != expected:
            (ROOT / 'build-out/long-double-actual.txt').write_bytes(actual)
            (ROOT / 'build-out/long-double-expected.txt').write_bytes(expected)
            for i, (a, b) in enumerate(zip(actual.splitlines(), expected.splitlines())):
                if a != b:
                    raise AssertionError(f'line {i+1}: seed {a!r}, gcc {b!r}')
            raise AssertionError('output length mismatch')
    print(f'PASS: x87 arithmetic, conditions, updates, conversions, ABI and {len(constants)} exact constants; {len(values)} operands')


if __name__ == '__main__':
    main()
