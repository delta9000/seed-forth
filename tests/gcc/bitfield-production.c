#include "bitfield-layout.h"
struct I global_i={5,-3,1};
void prod_a(struct A *p,long v){DO_A(p,v);}
void prod_b(struct B *p,long v){DO_B(p,v);}
void prod_c(struct C *p,long v){DO_C(p,v);}
void prod_u(union U *p,long v){DO_U(p,v);}
void prod_n(struct N *p,long v){DO_N(p,v);}
int prod_layout(void){return sizeof(struct A)+sizeof(struct B)*100+sizeof(struct C)*10000+sizeof(struct D)*1000000+sizeof(struct E)*10000000;}
int prod_init(void){struct I i={{7},{-4},1};return i.a==7&&i.b==-4&&i.c==1&&global_i.a==5&&global_i.b==-3&&global_i.c==1;}
long prod_read(struct A *a,struct C *c){long v;v=a->a+a->b+c->c;v+=(a->a < -1)+(-1 < a->a)*37;v+=(a->a++ == 7)*23;v+=(++a->b==-1)*29;return v;}
int prod_typed(double *d){struct A a;a.a=*d;a.b=-*d;*d=a.b;a.a+=2.75;return a.a==6&&a.b==-12&&*d==-12.0;}
