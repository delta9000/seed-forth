long oracle_eight(long a, long b, long c, long d, long e, long f, long g, long h);
signed char oracle_narrow(signed char x);
long oracle_variadic(int n, ...);
long sf_eight(long a, long b, long c, long d, long e, long f, long g, long h) {
  return a + 2*b + 3*c + 4*d + 5*e + 6*f + 7*g + 8*h;
}
signed char sf_char(signed char x) { return x; }
unsigned char sf_uchar(unsigned char x) { return x; }
short sf_short(short x) { return x; }
unsigned short sf_ushort(unsigned short x) { return x; }
int sf_int(int x) { return x; }
unsigned int sf_uint(unsigned int x) { return x; }
long sf_callback(long (*f)(long, long, long, long, long, long, long, long), long x) {
  return 1 + f(x,2,3,4,5,6,7,8);
}
long sf_pointer(long *p) { *p = *p + 17; return *p; }
long sf_call_host(void) {
  long n;
  n = oracle_eight(1,2,3,4,5,6,7,8);
  n = n + oracle_eight(oracle_narrow(255),2,3,4,5,6,7,8);
  if (oracle_narrow(255) != -1) return 1;
  if (oracle_variadic(8,1L,2L,3L,4L,5L,6L,7L,8L) != 36) return 2;
  return n;
}
long sf_switch(long x) {
  switch(x) { case 1: return oracle_eight(1,2,3,4,5,6,7,8); default: return 19; }
}
