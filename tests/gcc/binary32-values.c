/* Production-side scalar binary32 fixture. No binary32 literal parser is used. */
#include <stdarg.h>
float seed_from_i(int x) { return x; }
float seed_from_u(unsigned int x) { return x; }
float seed_from_l(long x) { return x; }
float seed_from_ul(unsigned long x) { return x; }
float seed_from_ll(long long x) { return x; }
float seed_from_ull(unsigned long long x) { return x; }
int seed_to_i(float x) { return x; }
unsigned int seed_to_u(float x) { return x; }
long seed_to_l(float x) { return x; }
unsigned long seed_to_ul(float x) { return x; }
long long seed_to_ll(float x) { return x; }
unsigned long long seed_to_ull(float x) { return x; }
float seed_narrow(double x) { return x; }
double seed_widen(float x) { return x; }
float seed_add(float x,float y) { return x+y; }
float seed_sub(float x,float y) { return x-y; }
float seed_mul(float x,float y) { return x*y; }
float seed_div(float x,float y) { return x/y; }
float seed_neg(float x) { return -x; }
float seed_plus(float x) { return +x; }
float seed_select(int n,float x,float y) { return n ? x : y; }
int seed_cmp(float x,float y) { return (x<y)|((x<=y)<<1)|((x>y)<<2)|((x>=y)<<3)|((x==y)<<4)|((x!=y)<<5); }
int seed_truth(float x,float y) { int n=0;if(x)n=8;return n|(!x)|((x&&y)<<1)|((x||y)<<2); }
float seed_compound(float x,double y) { x+=y;return x; }
float seed_mixed(float x,int y) { return (x+y)*y; }
double seed_mixed_double(float x,double y) { return x+y; }
float seed_assignment(double x) { float a,b;a=b=x;return a+b; }
struct cell32 { unsigned int before;float value;unsigned int after; };
float seed_memory(struct cell32 *p,float *a,int i,float x) { p->value=x;a[i]=p->value;return a[i]; }
float seed_qualified(volatile float *p,const float *q) { *p=*q;return *p; }
float seed_init(double x) { float a[3]={x,x+1,x+2};struct cell32 c={17,x,23};return a[0]+a[1]+a[2]+c.value; }
float seed_global;
float seed_global_store(float x) { seed_global=x;return seed_global; }
float seed_ten(float a,float b,float c,float d,float e,float f,float g,float h,float i,float j) { return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h+9*i+10*j; }
float seed_banks(long a,float b,long c,double d,long e,float f,long g,double h,long i,float j,long k,double l,long m,float n,float o,float p,float q,float r,float s) { return a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p+q+r+s; }
float seed_callback(float (*p)(float),float x) { return p(x)+p(x+1); }
extern float host_return32(float);
extern float host_ten32(float,float,float,float,float,float,float,float,float,float);
extern double host_var32(int,...);
extern double host_unproto32();
float seed_outbound(float x) { return host_ten32(x,x+1,x+2,x+3,x+4,x+5,x+6,x+7,x+8,x+9)+host_return32(x); }
double seed_varout(float x) { return host_var32(10,x,x+1,x+2,x+3,x+4,x+5,x+6,x+7,x+8,x+9); }
double seed_unproto(float x) { return host_unproto32(x); }
double seed_varin(float a,float b,float c,float d,float e,float f,float g,float h,float i,int n,...) { va_list ap;double x;va_start(ap,n);x=va_arg(ap,double);x+=va_arg(ap,double);va_end(ap);return a+b+c+d+e+f+g+h+i+x; }
