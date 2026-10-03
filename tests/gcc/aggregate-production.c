#include "aggregate-layout.h"
struct One agg_one(struct One p,long x) {p.a+=x;return p;}
struct Three agg_three(struct Three p) {p.a[2]+=p.a[0];return p;}
struct Pad agg_pad(struct Pad p) {p.a+=2;p.b+=300;return p;}
struct Pair agg_pair(struct Pair p,long x) {p.a+=x;p.b-=x;return p;}
struct Tail agg_tail(struct Tail p) {p.b+=3;return p;}
struct Large agg_large(struct Large p,long x) {p.a+=x;p.c-=x;return p;}
struct Nested agg_nested(struct Nested p) {p.p.b+=p.a[2];p.a[1]-=4;return p;}
struct Bits agg_bits(struct Bits p) {p.a+=3;p.b-=5;p.c+=99;return p;}
union Either agg_union(union Either p) {p.p.b+=p.p.a;return p;}
long agg_rollback(long a,long b,long c,long d,long e,struct Pair p,long f,struct Three t,long g) {
  return a+2*b+3*c+4*d+5*e+6*p.a+7*p.b+8*f+9*t.a[0]+10*t.a[2]+11*g;
}
struct Large agg_shift(long a,long b,long c,long d,long e,struct Pair p,long f,struct Large q) {
  q.a+=a+2*b+3*c+4*d+5*e;q.b+=p.a+2*p.b;q.c+=f;return q;
}
typedef struct Pair (*PairFn)(struct Pair,long);
static PairFn pick_pair(void) {return agg_pair;}
static int discard_count;
static struct Large discard_result(struct Large p) {discard_count++;return agg_large(p,1);}
static struct Pair global_pair={71,93};
static long mutate(void) {global_pair.a=900;global_pair.b=1000;return 5;}
static struct Pair nested(struct Pair p) {return agg_pair(agg_pair(p,4),7);}
static struct Large recurse(struct Large p,int n) {if(n==0)return p;p.a+=n;return recurse(p,n-1);}
static long local_array_argument(long x) {char p[117];p[116]=x;return p[116];}
long agg_caller(void) {
  struct Pair p={17,29};struct Large l={31,43,59}; struct Three t={{2,3,4}};
  struct Pair (*fp)(struct Pair,long)=host_pair;struct Large (*fl)(struct Large,long)=host_large;
  struct Pair r;struct Large q;long answer;
  r=fp(p,7);if(r.a!=24||r.b!=22)return 1;
  q=fl(l,11);if(q.a!=42||q.b!=43||q.c!=48)return 2;
  answer=host_rollback(1,2,3,4,5,p,6,t,7);
  if(answer!=1+4+9+16+25+102+203+48+18+40+77)return 3;
  p=nested(p);if(p.a!=28||p.b!=18)return 4;
  q=recurse(l,6);if(q.a!=52||q.b!=43||q.c!=59)return 5;
  r=agg_pair(global_pair,mutate());if(r.a!=76||r.b!=88)return 6;
  p=agg_pair(p,local_array_argument(3));if(p.a!=31||p.b!=15)return 7;
  q=agg_large(agg_large(l,3),agg_pair(p,2).b);if(q.a!=47||q.c!=43)return 8;
  r=agg_pair(p,1);q=agg_large(l,r.a);if(r.a!=32||r.b!=14||q.a!=63)return 9;
  p=r;p=p;r=p;if(p.a!=32||r.b!=14)return 10;
  if(sizeof(p)!=16||sizeof(l)!=24||sizeof(agg_large(l,mutate()))!=24)return 11;
  if(sizeof(p=r)!=16||sizeof(agg_pair(p,mutate()))!=16)return 12;
  if(global_pair.a!=900||global_pair.b!=1000)return 13;
  r=pick_pair()(p,4);if(r.a!=36||r.b!=10)return 14;
  if(100+agg_pair(p,3).a!=135)return 15;
  switch(p.a) {case 32:q=agg_large(l,5);break;default:return 16;}
  if(q.c!=54)return 17;
  (void)discard_result(l);if(discard_count!=1)return 18;
  (void)l;(void)discard_result(discard_result(l));if(discard_count!=3)return 19;
  return 0;
}
struct Three agg_read_three(struct Three *p) {return *p;}
struct Nine agg_read_nine(struct Nine *p) {return *p;}
double agg_double(struct Pair p) {return (double)p.a/(double)p.b;}
