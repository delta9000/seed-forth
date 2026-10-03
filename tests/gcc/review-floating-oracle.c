/* Host-only independent IEEE binary64/AMD64 oracle, linked at O0 and O2.
   Host-generated object bytes never enter the bootstrap route. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
#include <math.h>
#include <xmmintrin.h>

#define FROM(T,N) extern double review_from_##N(T);
FROM(signed char,char) FROM(unsigned char,uchar)
FROM(short,short) FROM(unsigned short,ushort)
FROM(int,int) FROM(unsigned int,uint)
FROM(long,long) FROM(unsigned long,ulong)
FROM(long long,ll) FROM(unsigned long long,ull)
#define TO(T,N) extern T review_to_##N(double *);
TO(signed char,char) TO(unsigned char,uchar)
TO(short,short) TO(unsigned short,ushort)
TO(int,int) TO(unsigned int,uint)
TO(long,long) TO(unsigned long,ulong)
TO(long long,ll) TO(unsigned long long,ull)
extern double review_add(double *,double *);
extern double review_sub(double *,double *);
extern double review_mul(double *,double *);
extern double review_div(double *,double *);
extern double review_neg(double *), review_positive(double *), review_identity(double *);
extern int review_compare(double *,double *), review_truth(double *,double *);
extern double review_select(int,double *,double *), review_local(double *);
extern void review_store(double *,double *);
struct review_cell { long before; double value; long after; };
extern void review_struct_store(struct review_cell *,double *);
extern double review_struct_load(struct review_cell *);
extern double review_array(double *,long);
extern double review_implicit_from_int(int), review_assign_int(long);
extern int review_implicit_to_int(double *);
extern long review_assign_double(double *);
extern double review_mix_left(double *,unsigned long), review_mix_right(unsigned long,double *);
extern double review_call_direct(double *,long);
extern double review_call_indirect(double (*)(double *,long),double *,long);
extern double review_call_nested(double *,double *);
extern double review_call_seven(long,long,long,long,long,long,double *);
extern double review_initialized(double *),review_initialized_int(long);
extern double review_compound_add(double *,double *),review_compound_sub(double *,double *);
extern double review_compound_mul(double *,double *),review_compound_div(double *,double *);
extern void review_global_store(double *);
extern double review_global_load(void);
extern int review_short_and(double *,long *),review_short_or(double *,long *),review_loop(double *);
static unsigned checks;
static uint64_t bits(double d) { uint64_t u; memcpy(&u,&d,8); return u; }
static double value(uint64_t u) { double d; memcpy(&d,&u,8); return d; }
static void fail(const char *name, uint64_t got, uint64_t want) {
  fprintf(stderr,"FAIL %s: got=%016llx want=%016llx\n",name,
          (unsigned long long)got,(unsigned long long)want);
}
static int equal(const char *name,double got,double want,int arithmetic) {
  checks++;
  if (arithmetic && isnan(got) && isnan(want)) return 0;
  if (bits(got)==bits(want)) return 0;
  fail(name,bits(got),bits(want)); return 1;
}
#define CHECK_INT(NAME,GOT,WANT) do { \
  uint64_t got_=(uint64_t)(GOT),want_=(uint64_t)(WANT); checks++; \
  if(got_!=want_){fail(NAME,got_,want_); return 1;} \
} while(0)
#define CHECK_FROM(T,N,VALUES) do { \
  const T a_[]=VALUES; \
  for(unsigned i_=0;i_<sizeof(a_)/sizeof(a_[0]);i_++){ \
    volatile T v_=a_[i_]; \
    if(equal("from_" #N,review_from_##N(v_),(double)v_,0)) return 1; \
  } \
} while(0)
#define CHECK_TO(T,N,VALUES) do { \
  double a_[]=VALUES; \
  for(unsigned i_=0;i_<sizeof(a_)/sizeof(a_[0]);i_++){ \
    volatile double v_=a_[i_]; \
    CHECK_INT("to_" #N,review_to_##N(&a_[i_]),(T)v_); \
  } \
} while(0)
#define VALUES(...) {__VA_ARGS__}

/* These host producers return through XMM0. Their integer/pointer arguments
   make them callable within the deliberately restricted target ABI. */
double review_host_value(double *p,long index) { return p[index]; }

int main(void) {
  unsigned csr_before=_mm_getcsr();
  if (sizeof(double)!=8 || sizeof(long)!=8 || CHAR_BIT!=8) return 77;
  CHECK_FROM(signed char,char,VALUES(-128,-1,0,1,127));
  CHECK_FROM(unsigned char,uchar,VALUES(0,1,127,128,255));
  CHECK_FROM(short,short,VALUES(-32768,-1,0,1,32767));
  CHECK_FROM(unsigned short,ushort,VALUES(0,1,32767,32768,65535));
  CHECK_FROM(int,int,VALUES(INT_MIN,-1,0,1,INT_MAX));
  CHECK_FROM(unsigned int,uint,VALUES(0,1,2147483647U,2147483648U,UINT_MAX));
  CHECK_FROM(long,long,VALUES(LONG_MIN,LONG_MIN+1,-9007199254740993L,
      -9007199254740991L,-1,0,1,9007199254740991L,9007199254740993L,
      9007199254740995L,LONG_MAX-1,LONG_MAX));
  CHECK_FROM(unsigned long,ulong,VALUES(0,1,9007199254740991UL,
      9007199254740993UL,9007199254740995UL,9223372036854775807UL,
      9223372036854775808UL,9223372036854775809UL,9223372036854776833UL,
      ULONG_MAX-2048,ULONG_MAX-1024,ULONG_MAX-1,ULONG_MAX));
  CHECK_FROM(long long,ll,VALUES(LLONG_MIN,-9007199254740993LL,0,
      9007199254740993LL,LLONG_MAX));
  CHECK_FROM(unsigned long long,ull,VALUES(0,9007199254740993ULL,
      9223372036854775808ULL,9223372036854776833ULL,ULLONG_MAX));
  /* Every floating-to-integer operand is finite and truncates into range.
     In particular, rounded (double)LONG_MAX / ULONG_MAX are NOT tested. */
  CHECK_TO(signed char,char,VALUES(-128.75,-128.0,-1.75,-0.5,0.0,1.75,127.75));
  CHECK_TO(unsigned char,uchar,VALUES(-0.5,0.0,0.5,1.75,128.0,255.75));
  CHECK_TO(short,short,VALUES(-32768.75,-32768.0,-1.75,0.0,1.75,32767.75));
  CHECK_TO(unsigned short,ushort,VALUES(-0.5,0.0,1.75,32768.0,65535.75));
  CHECK_TO(int,int,VALUES(-2147483648.75,-2147483648.0,-1.75,0.0,1.75,2147483647.75));
  CHECK_TO(unsigned int,uint,VALUES(-0.5,0.0,1.75,2147483648.0,4294967295.75));
  CHECK_TO(long,long,VALUES(-0x1p63,-0x1.fffffffffffffp62,-9007199254740991.0,
      -1.75,-0.5,0.0,1.75,9007199254740991.0,0x1.fffffffffffffp62));
  CHECK_TO(unsigned long,ulong,VALUES(-0.5,0.0,1.75,9007199254740991.0,
      0x1.fffffffffffffp62,0x1p63,0x1.0000000000001p63,0x1.fffffffffffffp63));
  CHECK_TO(long long,ll,VALUES(-0x1p63,-1.75,0.0,1.75,0x1.fffffffffffffp62));
  CHECK_TO(unsigned long long,ull,VALUES(-0.5,0.0,1.75,0x1p63,0x1.fffffffffffffp63));

  if(equal("zero initialized global",review_global_load(),0.0,0)
     ||equal("integer local initializer",review_initialized_int(LONG_MIN),(double)LONG_MIN,0)) return 1;
  const uint64_t raw[]={0,UINT64_C(0x8000000000000000),UINT64_C(0x3ff0000000000000),
    UINT64_C(0xbff0000000000000),UINT64_C(0x4008000000000000),UINT64_C(0x3fd5555555555555),
    1,UINT64_C(0x8000000000000001),UINT64_C(0x000fffffffffffff),
    UINT64_C(0x0010000000000000),UINT64_C(0x7fefffffffffffff),
    UINT64_C(0x7ff0000000000000),UINT64_C(0xfff0000000000000),
    UINT64_C(0x7ff8000000000042),UINT64_C(0xfff8000000000042)};
  double array[sizeof(raw)/sizeof(raw[0])];
  for(unsigned i=0;i<sizeof(raw)/sizeof(raw[0]);i++) array[i]=value(raw[i]);
  for(unsigned i=0;i<sizeof(raw)/sizeof(raw[0]);i++) {
    double a=array[i],out=value(UINT64_C(0xdeadbeefdeadbeef));
    struct review_cell cell={0x12345678,0.0,0x76543210};
    if(equal("identity",review_identity(&a),a,0)
      ||equal("unary positive",review_positive(&a),a,0)
      ||equal("unary negative",review_neg(&a),value(raw[i]^UINT64_C(0x8000000000000000)),0)
      ||equal("local",review_local(&a),a,0)
      ||equal("array",review_array(array,i),a,0)
      ||equal("direct host return",review_call_direct(array,i),a,0)
      ||equal("indirect host return",review_call_indirect(review_host_value,array,i),a,0)
      ||equal("seven GP args",review_call_seven(1,2,3,4,5,6,&a),a,0)) return 1;
    if(equal("double local initializer",review_initialized(&a),a,0)) return 1;
    review_global_store(&a);
    if(equal("global store/load",review_global_load(),a,0)) return 1;
    long count=0;
    CHECK_INT("short circuit and result",review_short_and(&a,&count),!!a);
    CHECK_INT("short circuit and effects",count,a?1:0);
    count=0;
    CHECK_INT("short circuit or result",review_short_or(&a,&count),1);
    CHECK_INT("short circuit or effects",count,a?0:1);
    CHECK_INT("while truth",review_loop(&a),a?1:0);
    review_store(&out,&a);
    if(equal("pointer store",out,a,0)) return 1;
    review_struct_store(&cell,&a);
    if(equal("struct store",cell.value,a,0)
      ||equal("struct load",review_struct_load(&cell),a,0)) return 1;
    CHECK_INT("struct before",cell.before,0x12345678);
    CHECK_INT("struct after",cell.after,0x76543210);
    for(unsigned j=0;j<sizeof(raw)/sizeof(raw[0]);j++) {
      double b=array[j]; volatile double va=a,vb=b;
      if(equal("add",review_add(&a,&b),va+vb,1)
        ||equal("subtract",review_sub(&a,&b),va-vb,1)
        ||equal("multiply",review_mul(&a,&b),va*vb,1)
        ||equal("divide",review_div(&a,&b),va/vb,1)
        ||equal("nested host returns",review_call_nested(&a,&b),va/vb,1)
        ||equal("select true",review_select(1,&a,&b),a,0)
        ||equal("select false",review_select(0,&a,&b),b,0)) return 1;
      if (j==4) {
        if(equal("compound add",review_compound_add(&a,&b),va+vb,1)
          ||equal("compound subtract",review_compound_sub(&a,&b),va-vb,1)
          ||equal("compound multiply",review_compound_mul(&a,&b),va*vb,1)
          ||equal("compound divide",review_compound_div(&a,&b),va/vb,1)) return 1;
      }
      int comp=(va<vb)|((va<=vb)<<1)|((va>vb)<<2)|((va>=vb)<<3)|((va==vb)<<4)|((va!=vb)<<5);
      int truth=(va?8:0)|(!va)|((va&&vb)<<1)|((va||vb)<<2);
      CHECK_INT("comparisons",review_compare(&a,&b),comp);
      CHECK_INT("truth",review_truth(&a,&b),truth);
    }
  }
  double p=7.0,q=-1.75;
  if(equal("implicit return to double",review_implicit_from_int(INT_MIN),(double)INT_MIN,0)
    ||equal("implicit assignment to double",review_assign_int(LONG_MIN),(double)LONG_MIN,0)
    ||equal("mixed double/integer",review_mix_left(&p,ULONG_MAX),p/(double)ULONG_MAX,0)
    ||equal("mixed integer/double",review_mix_right(ULONG_MAX,&p),(double)ULONG_MAX/p,0)) return 1;
  CHECK_INT("implicit return to int",review_implicit_to_int(&q),-1);
  CHECK_INT("implicit assignment to long",review_assign_double(&q),-1);
  CHECK_INT("MXCSR control preserved",_mm_getcsr()&~0x3fU,csr_before&~0x3fU);
  printf("PASS: scalar floating host oracle %u checks\n",checks);
  return 0;
}
