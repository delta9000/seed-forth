#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <stdarg.h>
#include "binary32-prototypes.h"
static unsigned long checks;
static uint64_t state=0x6a09e667f3bcc909ULL;
static uint64_t rnd(void){state^=state<<13;state^=state>>7;state^=state<<17;return state;}
static float from32(uint32_t u){float x;memcpy(&x,&u,4);return x;}
static uint32_t bits32(float x){uint32_t u;memcpy(&u,&x,4);return u;}
static double from64(uint64_t u){double x;memcpy(&x,&u,8);return x;}
static uint64_t bits64(double x){uint64_t u;memcpy(&u,&x,8);return u;}
static void fail(const char *s,uint64_t a,uint64_t b){fprintf(stderr,"FAIL %s: %016llx != %016llx at %lu\n",s,(unsigned long long)a,(unsigned long long)b,checks);exit(1);}
static void eq(const char*s,uint64_t a,uint64_t b){checks++;if(a!=b)fail(s,a,b);}
static void feq(const char*s,float a,float b){checks++;if(isnan(a)&&isnan(b))return;if(bits32(a)!=bits32(b))fail(s,bits32(a),bits32(b));}
static void deq(const char*s,double a,double b){checks++;if(isnan(a)&&isnan(b))return;if(bits64(a)!=bits64(b))fail(s,bits64(a),bits64(b));}
float host_return32(float x){return x+3;}
float host_ten32(float a,float b,float c,float d,float e,float f,float g,float h,float i,float j){return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h+9*i+10*j;}
double host_var32(int n,...){va_list ap;double sum=0;int i;va_start(ap,n);for(i=0;i<n;i++)sum+=va_arg(ap,double);va_end(ap);return sum;}
double host_unproto32(double x){return x+3;}
#define F1(n,x) feq(#n,seed_##n(x),oracle_##n(x))
#define F2(n,x,y) feq(#n,seed_##n(x,y),oracle_##n(x,y))
#define D1(n,x) deq(#n,seed_##n(x),oracle_##n(x))
#define E1(n,x) eq(#n,(uint64_t)seed_##n(x),(uint64_t)oracle_##n(x))
static void one(uint32_t u,uint32_t v){float x=from32(u),y=from32(v);struct cell32 a={0xdeadbeef,0,0xaabbccdd},b=a;float aa[3]={11,12,13},bb[3]={11,12,13},z=0,w=0;
 F2(add,x,y);F2(sub,x,y);F2(mul,x,y);F2(div,x,y);F1(neg,x);F1(plus,x);
 eq("identity-payload",bits32(seed_plus(x)),u);
 eq("negate-payload",bits32(seed_neg(x)),u^0x80000000U);
 eq("compare",seed_cmp(x,y),oracle_cmp(x,y));eq("truth",seed_truth(x,y),oracle_truth(x,y));
 feq("select",seed_select(u&1,x,y),oracle_select(u&1,x,y));D1(widen,x);
 feq("memory",seed_memory(&a,aa,1,x),oracle_memory(&b,bb,1,x));eq("before",a.before,b.before);eq("after",a.after,b.after);
 eq("array-before",bits32(aa[0]),bits32(bb[0]));eq("array-after",bits32(aa[2]),bits32(bb[2]));eq("array-value",bits32(aa[1]),u);
 eq("qualified",bits32(seed_qualified(&z,&x)),bits32(oracle_qualified(&w,&x)));eq("global",bits32(seed_global_store(x)),u);
 if(isfinite(x)){
  if(x>=-2147483648.0 && x<2147483648.0){E1(to_i,x);}
  if(x>=0 && (double)x<4294967296.0){E1(to_u,x);}
  if((double)x>=-9223372036854775808.0 && (double)x<9223372036854775808.0){E1(to_l,x);E1(to_ll,x);}
  if(x>=0 && (double)x<18446744073709551616.0){E1(to_ul,x);E1(to_ull,x);}
 }
}
static void integers(uint64_t u){long s;memcpy(&s,&u,8);F1(from_i,(int)s);F1(from_u,(unsigned)u);F1(from_l,s);F1(from_ul,(unsigned long)u);F1(from_ll,(long long)s);F1(from_ull,(unsigned long long)u);}
int main(void){unsigned i,j;static const uint32_t fs[]={0,0x80000000,1,2,0x80000001,0x007fffff,0x00800000,0x00800001,0x3f000000,0x3f800000,0x3f800001,0x3f7fffff,0xbf800000,0x4b7fffff,0x4b800000,0x4b800001,0xcb800001,0x4effffff,0x4f000000,0x4f7fffff,0x4f800000,0xceffffff,0xcf000000,0x5effffff,0x5f000000,0x5f000001,0x5f7fffff,0x5f800000,0xdeffffff,0xdf000000,0x7f7fffff,0xff7fffff,0x7f800000,0xff800000,0x7fc00000,0xffc00001,0x7fc12345};
 static const uint64_t is[]={0,1,2,0xffffff,0x1000000,0x1000001,0x1000003,0x1ffffff,0x7fffffff,0x80000000,0xffffffff,0x100000001ULL,0x7fffffffffffffffULL,0x8000000000000000ULL,0x8000000000000001ULL,0xffffffffffffffffULL,0x4000004000000001ULL,0xbfffffbfffffffffULL};
 static const uint64_t ds[]={0,0x8000000000000000ULL,1,0x36a0000000000000ULL,0x3690000000000000ULL,0x3690000000000001ULL,0x380fffffc0000000ULL,0x3810000000000000ULL,0x3ff0000010000000ULL,0x3ff0000010000001ULL,0x3ff000000fffffffULL,0x3ff0000030000000ULL,0x47efffffe0000000ULL,0x47effffff0000000ULL,0x47efffffefffffffULL,0x47f0000000000000ULL,0x7ff0000000000000ULL,0xfff0000000000000ULL,0x7ff8000000001234ULL};
 for(i=0;i<sizeof(fs)/sizeof(*fs);i++)for(j=0;j<sizeof(fs)/sizeof(*fs);j++)one(fs[i],fs[j]);
 for(i=0;i<sizeof(is)/sizeof(*is);i++)integers(is[i]);
 for(i=0;i<sizeof(ds)/sizeof(*ds);i++)F1(narrow,from64(ds[i]));
 for(i=0;i<12000;i++){one((uint32_t)rnd(),(uint32_t)rnd());integers(rnd());{double d=from64(rnd());F1(narrow,d);}}
 for(i=0;i<500;i++){float x=(float)(int)(rnd()%1000000)-500000;double y=from64(0x3ff0000000000000ULL|(rnd()&0xfffffffffffffULL));F2(compound,x,y);F2(mixed,x,7);deq("mixed-double",seed_mixed_double(x,y),oracle_mixed_double(x,y));F1(assignment,y);F1(init,y);F1(outbound,x);D1(varout,x);D1(unproto,x);feq("callback",seed_callback(host_return32,x),oracle_callback(host_return32,x));
 feq("ten",seed_ten(x,2,3,4,5,6,7,8,9,10),oracle_ten(x,2,3,4,5,6,7,8,9,10));
 feq("banks",seed_banks(1,x,3,y,5,x,7,y,9,x,11,y,13,x,x,x,x,x,x),oracle_banks(1,x,3,y,5,x,7,y,9,x,11,y,13,x,x,x,x,x,x));
 deq("varin",seed_varin(x,2,3,4,5,6,7,8,9,2,y,y+1),oracle_varin(x,2,3,4,5,6,7,8,9,2,y,y+1));}
 printf("PASS: %lu binary32 comparisons, deterministic seed 6a09e667f3bcc909\n",checks);return 0;}
