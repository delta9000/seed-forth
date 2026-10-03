/* Independent scalar binary64 review fixture: compiled only by seed Forth.
   No floating parameters are needed; double objects enter through pointers. */
double review_from_char(signed char x) { return (double)x; }
double review_from_uchar(unsigned char x) { return (double)x; }
double review_from_short(short x) { return (double)x; }
double review_from_ushort(unsigned short x) { return (double)x; }
double review_from_int(int x) { return (double)x; }
double review_from_uint(unsigned int x) { return (double)x; }
double review_from_long(long x) { return (double)x; }
double review_from_ulong(unsigned long x) { return (double)x; }
double review_from_ll(long long x) { return (double)x; }
double review_from_ull(unsigned long long x) { return (double)x; }
signed char review_to_char(double *p) { return (signed char)*p; }
unsigned char review_to_uchar(double *p) { return (unsigned char)*p; }
short review_to_short(double *p) { return (short)*p; }
unsigned short review_to_ushort(double *p) { return (unsigned short)*p; }
int review_to_int(double *p) { return (int)*p; }
unsigned int review_to_uint(double *p) { return (unsigned int)*p; }
long review_to_long(double *p) { return (long)*p; }
unsigned long review_to_ulong(double *p) { return (unsigned long)*p; }
long long review_to_ll(double *p) { return (long long)*p; }
unsigned long long review_to_ull(double *p) { return (unsigned long long)*p; }
double review_add(double *p, double *q) { return *p+*q; }
double review_sub(double *p, double *q) { return *p-*q; }
double review_mul(double *p, double *q) { return *p**q; }
double review_div(double *p, double *q) { return *p / *q; }
double review_neg(double *p) { return -*p; }
double review_positive(double *p) { return +*p; }
double review_identity(double *p) { return *p; }
int review_compare(double *p, double *q) {
  return (*p<*q) | ((*p<=*q)<<1) | ((*p>*q)<<2)
      | ((*p>=*q)<<3) | ((*p==*q)<<4) | ((*p!=*q)<<5);
}
int review_truth(double *p, double *q) {
  int n;
  n=0;
  if (*p) n=8;
  return n | (!*p) | ((*p&&*q)<<1) | ((*p||*q)<<2);
}
double review_select(int test, double *p, double *q) { return test ? *p : *q; }
double review_local(double *p) { double x; x=*p; return x; }
void review_store(double *p, double *q) { *p=*q; }
struct review_cell { long before; double value; long after; };
void review_struct_store(struct review_cell *p, double *q) { p->value=*q; }
double review_struct_load(struct review_cell *p) { return p->value; }
double review_array(double *p, long i) { return p[i]; }
double review_implicit_from_int(int x) { return x; }
int review_implicit_to_int(double *p) { return *p; }
double review_assign_int(long x) { double d; d=x; return d; }
long review_assign_double(double *p) { long x; x=*p; return x; }
double review_mix_left(double *p, unsigned long x) { return *p/x; }
double review_mix_right(unsigned long x, double *p) { return x / *p; }
extern double review_host_value(double *, long);
double review_call_direct(double *p, long n) { return review_host_value(p,n); }
double review_call_indirect(double (*f)(double *,long), double *p, long n) {
  return f(p,n);
}
double review_call_nested(double *p, double *q) {
  return review_host_value(p,0)/review_host_value(q,0);
}
double review_call_seven(long a, long b, long c, long d, long e, long f,
                         double *p) {
  if (a+b+c+d+e+f!=21) return (double)-1;
  return review_host_value(p,0);
}
double review_initialized(double *p) { double d=*p; return d; }
double review_initialized_int(long x) { double d=x; return d; }
double review_compound_add(double *p,double *q) { double d=*p; d+=*q; return d; }
double review_compound_sub(double *p,double *q) { double d=*p; d-=*q; return d; }
double review_compound_mul(double *p,double *q) { double d=*p; d*=*q; return d; }
double review_compound_div(double *p,double *q) { double d=*p; d/=*q; return d; }
double review_global;
void review_global_store(double *p) { review_global=*p; }
double review_global_load(void) { return review_global; }
int review_short_and(double *p,long *count) { return *p && ++*count; }
int review_short_or(double *p,long *count) { return *p || ++*count; }
int review_loop(double *p) { double d=*p; int n=0; while(d) { n++; d=0; } return n; }
