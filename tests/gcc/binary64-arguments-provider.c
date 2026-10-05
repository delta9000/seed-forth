#include "binary64-arguments.h"
#include <stdarg.h>
double seed_one(double x){return x*2.0+0.5;}
double seed_mix(double d0, long g0, double d1, long g1, double d2, long g2, double d3, long g3, double d4, long g4, double d5, long g5, double d6, long g6, double d7, long g7, double d8, double d9){return d0*1 + g0*11 + d1*2 + g1*12 + d2*3 + g2*13 + d3*4 + g3*14 + d4*5 + g4*15 + d5*6 + g5*16 + d6*7 + g6*17 + d7*8 + g7*18 + d8*9 + d9*10;}
double seed_var(long a,double x,long b,double y,...){
 va_list ap; va_list cp; int i; double s=a+x+b+y;
 va_start(ap,y); va_copy(cp,ap);
 for(i=0;i<10;i++){s+=va_arg(ap,double);s+=va_arg(ap,long);}
 if(va_arg(cp,double)!=1.25)return -1.0;
 va_end(cp);va_end(ap);return s;
}
double seed_over(double d0, long g0, double d1, long g1, double d2, long g2, double d3, long g3, double d4, long g4, double d5, long g5, double d6, long g6, double d7, long g7, double d8, double d9,...){
 va_list ap; double x; long y; double z; va_start(ap,d9);
 x=va_arg(ap,double);y=va_arg(ap,long);z=va_arg(ap,double);va_end(ap);
 return d0*1 + g0*11 + d1*2 + g1*12 + d2*3 + g2*13 + d3*4 + g3*14 + d4*5 + g4*15 + d5*6 + g5*16 + d6*7 + g6*17 + d7*8 + g7*18 + d8*9 + d9*10+x+y+z;
}
double seed_rollback(long a,double x,long b,long c,long d,long e,struct pair p,double y,long f,double z){
 return a+b+c+d+e+p.a*3+p.b*5+x*7+y*11+f*13+z*17;
}
struct triple seed_memory(double x,struct pair p,struct triple q,double y,long z){
 struct triple r; r.a=q.a+p.a+(long)x;r.b=q.b+p.b+(long)y;r.c=q.c+z;return r;
}

double seed_echo(double x){return x;}
double seed_knr(x) double x; {return x+0.25;}

double seed_fp_first(double d0, double d1, double d2, double d3, double d4, double d5, double d6, double d7, double d8, double d9,long a,long b){return d0*1+d1*2+d2*3+d3*4+d4*5+d5*6+d6*7+d7*8+d8*9+d9*10+a*11+b*12;}
double seed_stack_echo(double d0, double d1, double d2, double d3, double d4, double d5, double d6, double d7, double d8, double d9){return d9;}
long seed_integer(long x){return x;}
