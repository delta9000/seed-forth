/* Same-record conditional values and synthesized for-condition metadata. */
struct R { long v[3]; };
struct Nested { struct R r; long *p; };
union U { long v[3]; long first; };
struct F { double x; long y; };
static int effects;
static long sum(long *p) { return p[0]+p[1]+p[2]; }
/* A new function must not inherit the preceding record return metadata. */
static struct R made(long x) { struct R r={{x,x+1,x+2}}; effects++; return r; }
static int loop_after_return(void) { for (;;) { return 7; } }
static int loop_after_assignment(void) {
  struct R a={{1,2,3}},b={{4,5,6}};
  a=b;
  for (;;) { if(a.v[0]!=4)return 1; break; }
  for (a=b;;) { if(a.v[2]!=6)return 2; break; }
  for (;;) { a=b; for (;;) { break; } break; }
  return 0;
}
int main(void) {
  struct R a={{1,2,3}},b={{4,5,6}},c={{7,8,9}},r;
  struct Nested n={{{11,12,13}},a.v},m={{{21,22,23}},b.v};
  union U u={{31,32,33}},v={{41,42,43}},w;
  struct F f={1.25,7},g={2.5,8},h;
  long *p,*q; long value; int flag=1;
  if(loop_after_return()!=7||loop_after_assignment())return 1;
  r=flag?a:b;if(sum(r.v)!=6)return 2;
  r=!flag?a:b;if(sum(r.v)!=15)return 3;
  r=flag?made(10):made(20);if(effects!=1||sum(r.v)!=33)return 4;
  r=!flag?made(30):made(40);if(effects!=2||sum(r.v)!=123)return 5;
  r=flag?(!flag?a:b):c;if(sum(r.v)!=15)return 6;
  value=(p=(flag?a:b).v,a.v[0]=99,sum(p));if(value!=6)return 7;
  a.v[0]=1;
  value=(p=(flag?a:b).v,q=(!flag?a:c).v,a.v[0]=99,c.v[0]=88,sum(p)+sum(q));
  if(value!=30)return 8;
  a.v[0]=1;c.v[0]=7;
  value=(p=(flag?(!flag?a:b):c).v,b.v[0]=77,sum(p));if(value!=15)return 9;
  b.v[0]=4;
  value=(p=(flag?n:m).r.v,n.r.v[0]=66,sum(p));if(value!=36)return 10;
  *(flag?n:m).p=17;if(a.v[0]!=17)return 11;
  w=flag?u:v;if(w.v[2]!=33)return 12;
  h=flag?f:g;if(h.x!=1.25||h.y!=7)return 13;
  if(sizeof(flag?made(1):made(2))!=24||effects!=2)return 14;
  if(sizeof((flag?a:b).v)!=24||sizeof((flag?n:m).r)!=24)return 15;
  if(sizeof(flag?f:g)!=16)return 16;
  a=flag?a:b;if(a.v[0]!=17||a.v[2]!=3)return 17;
  value=(p=(flag?made(50):made(60)).v,q=(flag?made(70):made(80)).v,sum(p)+sum(q));
  if(value!=366||effects!=4)return 18;
  return 0;
}
