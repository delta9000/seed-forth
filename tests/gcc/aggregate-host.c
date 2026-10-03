#include "aggregate-layout.h"
struct Pair host_pair(struct Pair p,long x) {p.a+=x;p.b-=x;return p;}
struct Large host_large(struct Large p,long x) {p.a+=x;p.c-=x;return p;}
long host_rollback(long a,long b,long c,long d,long e,struct Pair p,long f,struct Three t,long g) {
  return a+2*b+3*c+4*d+5*e+6*p.a+7*p.b+8*f+9*t.a[0]+10*t.a[2]+11*g;
}
int main(void) {
  struct One o={-101};struct Three t={{11,22,33}};struct Pad d={-7,10003};
  struct Pair p={101,203};struct Tail tail={987,41};struct Large l={17,23,31};
  struct Nested n={{2,190},{7,11,13}};struct Bits b={6,-93,4000000000UL};
  union Either u={{19,37}};struct Large q;long answer;
  o=agg_one(o,20);if(o.a!=-81)return 21;
  t=agg_three(t);if(t.a[0]!=11||t.a[1]!=22||t.a[2]!=44)return 22;
  d=agg_pad(d);if(d.a!=-5||d.b!=10303)return 23;
  p=agg_pair(p,7);if(p.a!=108||p.b!=196)return 24;
  tail=agg_tail(tail);if(tail.a!=987||tail.b!=44)return 25;
  q=agg_large(l,5);if(q.a!=22||q.b!=23||q.c!=26||l.a!=17)return 26;
  n=agg_nested(n);if(n.p.a!=2||n.p.b!=203||n.a[0]!=7||n.a[1]!=7||n.a[2]!=13)return 27;
  b=agg_bits(b);if(b.a!=1||b.b!=-98||b.c!=4000000099UL)return 28;
  u=agg_union(u);if(u.p.a!=19||u.p.b!=56)return 29;
  answer=agg_rollback(1,2,3,4,5,p,6,t,7);
  if(answer!=1+4+9+16+25+6*108+7*196+48+99+440+77)return 30;
  q=agg_shift(1,2,3,4,5,p,6,l);
  if(q.a!=72||q.b!=523||q.c!=37)return 31;
  return agg_caller();
}
