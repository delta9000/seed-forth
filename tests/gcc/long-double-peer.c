/* Pure data-movement peers; built by host GCC or by the Forth compiler. */
#include <stdarg.h>
#include <string.h>
#include "long-double.h"

long double host_id(long double x) { return x; }

long double host_pick(int k, long double a, double d, long double b, long g, long double c)
{
  if (k == 0) return a;
  if (k == 1) return b;
  if (k == 2) return c;
  return d == 2.5 && g == 77 ? a : b;
}

long double host_many(long a, long b, long c, long d, long e, long f, long double x, long g, long double y)
{
  if (a + b + c + d + e + f + g == 28) return x;
  return y;
}

/* host_va(2, ...) takes the third of four long doubles; host_va(3, ...)
   skips a long double and a double and returns the long double after. */
long double host_va(int n, ...)
{
  va_list ap;
  long double r;
  va_start(ap, n);
  if (n == 3) {
    r = va_arg(ap, long double);
    (void) va_arg(ap, double);
    r = va_arg(ap, long double);
  } else {
    (void) va_arg(ap, long double);
    (void) va_arg(ap, long double);
    r = va_arg(ap, long double);
  }
  va_end(ap);
  return r;
}

/* A named long double occupies the stack before the first unnamed slot. */
long double host_va_named(long double a, int n, ...)
{
  va_list ap;
  long double r = a;
  int i;
  va_start(ap, n);
  for (i = 0; i < n; i++) {
    if (va_arg(ap, int) != i) return a;
    r = va_arg(ap, long double);
  }
  va_end(ap);
  return r;
}

struct ld_pad host_pad(struct ld_pad p, long double y)
{
  p.x = y;
  p.k = p.k + 1;
  return p;
}

struct ld_one host_one(struct ld_one o) { return o; }
union ld_mix host_mix(union ld_mix m) { return m; }

struct ld_pair host_pair(long double a, struct ld_pair p, long double b)
{
  struct ld_pair r;
  r.a = b;
  r.b = p.a;
  (void) a;
  return r;
}

long double host_knr(long double x, int k) { return k == 3 ? x : x; }

int host_same(const long double *a, const long double *b)
{
  return memcmp(a, b, 10) == 0;
}
