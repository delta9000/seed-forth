struct A {unsigned a:3; signed b:5; unsigned c:24; char d;};
struct B {char head;unsigned a:20;unsigned b:20;unsigned:0;signed c:7;unsigned:3;unsigned d:22;char tail;};
struct C {unsigned long a:32,b:31;long c:32;unsigned long d:1;unsigned e:32;long f:64;char tail;};
struct D {char a;unsigned:1;char b;};
struct E {unsigned a:4;unsigned:0;unsigned b:8;unsigned long:0;char z;};
union U {unsigned a:3;signed b:17;unsigned long c:32;char bytes[12];};
struct N {char h; struct {unsigned a:12; signed b:20;};char t;};
struct I {unsigned:3;unsigned a:3;signed b:3;unsigned:0;unsigned c:1;};
#define DO_A(p,v) (p)->a=v;(p)->b=v/3;(p)->c=v*19;(p)->a+=7;(p)->b++;(p)->c^=123;(p)->d=53
#define DO_B(p,v) (p)->a=v;(p)->b=v*5;(p)->c=v/7;(p)->d=v*31;(p)->a>>=3;(p)->c-=2;(p)->d++;(p)->head=23;(p)->tail=49
#define DO_C(p,v) (p)->a=v;(p)->b=v*3;(p)->c=v/7;(p)->d=v;(p)->e=v;(p)->f=v;(p)->a^=4294967296UL;(p)->b++;(p)->c-=7;(p)->f++;(p)->tail=89
#define DO_U(p,v) (p)->c=v;(p)->b=v/9;(p)->a=v
#define DO_N(p,v) (p)->a=v;(p)->b=v/3;(p)->a++;(p)->b-=2;(p)->h=23;(p)->t=49
void prod_a(struct A*,long);void prod_b(struct B*,long);void prod_c(struct C*,long);void prod_u(union U*,long);void prod_n(struct N*,long);
int prod_layout(void);int prod_init(void);long prod_read(struct A*,struct C*);
int prod_typed(double*);
