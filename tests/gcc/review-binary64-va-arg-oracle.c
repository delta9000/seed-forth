#include <stdarg.h>
#include <stdio.h>
#include <string.h>
struct item { long value; double next; };
int review_contexts(unsigned long, unsigned long,...);
int review_drain(va_list, const char *, const unsigned long *);
int review_named8(long,long,long,long,long,long,const char *,const unsigned long *,...);
static unsigned long bits(double d) { unsigned long u; memcpy(&u,&d,8); return u; }
static int named_fp8(const char *shape,const unsigned long *want,
                      double a,double b,double c,double d,double e,double f,double g,double h,...)
{
    va_list list;
    int result;
    if (a+b+c+d+e+f+g+h != 36.0) return 101;
    va_start(list,h);
    result=review_drain(list,shape,want);
    va_end(list);
    return result;
}
static int after_extended(const char *shape,const unsigned long *want,...)
{
    va_list list;
    long double extended;
    int result;
    va_start(list,want);
    extended=va_arg(list,long double);
    if (extended != 23.5L) return 102;
    result=review_drain(list,shape,want);
    va_end(list);
    return result;
}
int main(void)
{
    struct item one={345,0}, two={678,0};
    double value=-0.0;
    unsigned long want[28];
    int result, i;
#define CHECK(expr) do { result=(expr); if(result) { fprintf(stderr,"line %d result %d\n",__LINE__,result); return 1; } } while(0)
    CHECK(review_contexts(bits(value),bits(19.5),value,19.5,&one,&two,&value));
    for(i=0;i<14;++i) { want[2*i]=bits(i+0.25); want[2*i+1]=401UL+i; }
    CHECK(review_named8(1L,2L,3L,4L,5L,6L,"dldldldldldldldldldldldldldl",want,
       0.25,401UL,1.25,402UL,2.25,403UL,3.25,404UL,4.25,405UL,5.25,406UL,6.25,407UL,
       7.25,408UL,8.25,409UL,9.25,410UL,10.25,411UL,11.25,412UL,12.25,413UL,13.25,414UL));
    CHECK(named_fp8("dldldldldldldldldldldldldldl",want,1.,2.,3.,4.,5.,6.,7.,8.,
       0.25,401UL,1.25,402UL,2.25,403UL,3.25,404UL,4.25,405UL,5.25,406UL,6.25,407UL,
       7.25,408UL,8.25,409UL,9.25,410UL,10.25,411UL,11.25,412UL,12.25,413UL,13.25,414UL));
    CHECK(after_extended("dldldldldldldldldldldldldldl",want,23.5L,
       0.25,401UL,1.25,402UL,2.25,403UL,3.25,404UL,4.25,405UL,5.25,406UL,6.25,407UL,
       7.25,408UL,8.25,409UL,9.25,410UL,10.25,411UL,11.25,412UL,12.25,413UL,13.25,414UL));
    puts("PASS: independent binary64 list aliases, record contexts, overflow alignment and host cursors");
    return 0;
}
