/* Oracle only: no bytes built from this file enter bootstrap products. */
#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
long sf_eight(long,long,long,long,long,long,long,long);
signed char sf_char(signed char);
unsigned char sf_uchar(unsigned char);
short sf_short(short);
unsigned short sf_ushort(unsigned short);
int sf_int(int);
unsigned int sf_uint(unsigned int);
long sf_callback(long (*)(long,long,long,long,long,long,long,long),long);
long sf_pointer(long *);
long sf_call_host(void);
long sf_switch(long);
long oracle_eight(long a,long b,long c,long d,long e,long f,long g,long h) {
  return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h;
}
signed char oracle_narrow(signed char x) { return x; }
long oracle_variadic(int n, ...) {
  long sum=0; va_list ap; va_start(ap,n);
  while(n--) sum+=va_arg(ap,long);
  va_end(ap); return sum;
}
int main(void) {
  long x=25;
  if(sf_eight(1,2,3,4,5,6,7,8)!=204) return 1;
  if(sf_char(-128)!=-128 || sf_uchar(255)!=255) return 2;
  if(sf_short(-32768)!=-32768 || sf_ushort(65535)!=65535) return 3;
  if(sf_int(INT32_MIN)!=INT32_MIN || sf_uint(UINT32_MAX)!=UINT32_MAX) return 4;
  if(sf_callback(oracle_eight,1)!=205) return 5;
  if(sf_pointer(&x)!=42 || x!=42) return 6;
  if(sf_call_host()!=406) return 7;
  if(sf_switch(1)!=204 || sf_switch(2)!=19) return 8;
  puts("PASS: Forth/System V bilateral scalar interoperability"); return 0;
}
