/* Forth-built long double data movement: no long double arithmetic. */
#include <stdarg.h>
#include <stddef.h>
#include <string.h>
#include "long-double.h"

struct ld_align { char c; long double x; };

long seed_layout(long *out)
{
  long n = 0;
  out[n++] = sizeof(long double);
  out[n++] = sizeof(ld_t);
  out[n++] = offsetof(struct ld_align, x);
  out[n++] = sizeof(struct ld_align);
  out[n++] = sizeof(struct ld_pad);
  out[n++] = offsetof(struct ld_pad, x);
  out[n++] = offsetof(struct ld_pad, k);
  out[n++] = sizeof(struct ld_one);
  out[n++] = sizeof(union ld_mix);
  out[n++] = sizeof(struct ld_pair);
  out[n++] = offsetof(struct ld_pair, b);
  out[n++] = sizeof(struct ld_nest);
  out[n++] = offsetof(struct ld_nest, o);
  out[n++] = offsetof(struct ld_nest, m);
  out[n++] = offsetof(struct ld_nest, t);
  out[n++] = sizeof(union ld_bfd_args);
  out[n++] = sizeof(long double[3]);
  out[n++] = sizeof(long double *);
  return n;
}

long double seed_id(long double x) { return x; }

long double seed_pick(int k, long double a, double d, long double b, long g, long double c)
{
  if (k == 0) return a;
  if (k == 1) return b;
  if (k == 2) return c;
  return d == 2.5 && g == 77 ? a : b;
}

long double seed_many(long a, long b, long c, long d, long e, long f, long double x, long g, long double y)
{
  if (a + b + c + d + e + f + g == 28) return x;
  return y;
}

/* Every variadic argument is a long double; return the n-th, rescanning a copy. */
long double seed_va(int n, ...)
{
  va_list ap, again;
  long double first, r;
  int i;
  va_start(ap, n);
  first = va_arg(ap, long double);
  va_copy(again, ap);
  r = first;
  for (i = 1; i <= n; i++) r = va_arg(again, long double);
  va_end(again);
  va_end(ap);
  return r;
}


/* A named long double occupies the stack before the first unnamed slot. */
long double seed_va_named(long double a, int n, ...)
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

/* Tagged list: 0 int i, 1 double i+0.5, 3 long 1000*i, 2 long double kept. */
void seed_va_list(long double *out, int n, ...)
{
  va_list ap;
  int i, tag, kept = 0, bad = 0;
  va_start(ap, n);
  for (i = 0; i < n; i++) {
    tag = va_arg(ap, int);
    if (tag == 0) { if (va_arg(ap, int) != i) bad++; }
    else if (tag == 1) { if (va_arg(ap, double) != i + 0.5) bad++; }
    else if (tag == 3) { if (va_arg(ap, long) != 1000L * i) bad++; }
    else out[kept++] = va_arg(ap, long double);
  }
  va_end(ap);
  if (bad) memset(out, 0x5a, 16 * kept);
}

/* Reduction of bfd.c: _bfd_doprnt_scan types, error_handler_internal fetches. */
static void seed_bfd_fetch(const char *fmt, union ld_bfd_args *args, va_list ap)
{
  unsigned int i, arg_count = strlen(fmt);
  for (i = 0; i < arg_count; i++)
    args[i].type = fmt[i] == 'i' ? Int : fmt[i] == 'l' ? Long : fmt[i] == 'L' ? LongLong
      : fmt[i] == 'd' ? Double : fmt[i] == 'D' ? LongDouble : fmt[i] == 'p' ? Ptr : Bad;
  for (i = 0; i < arg_count; i++)
    {
      switch (args[i].type)
	{
	case Int:
	  args[i].i = va_arg (ap, int);
	  break;
	case Long:
	  args[i].l = va_arg (ap, long);
	  break;
	case LongLong:
	  args[i].ll = va_arg (ap, long long);
	  break;
	case Double:
	  args[i].d = va_arg (ap, double);
	  break;
	case LongDouble:
	  args[i].ld = va_arg (ap, long double);
	  break;
	case Ptr:
	  args[i].p = va_arg (ap, void *);
	  break;
	default:
	  args[i].i = -1;
	}
    }
}

void seed_bfd(const char *fmt, union ld_bfd_args *args, ...)
{
  va_list ap;
  va_start(ap, args);
  seed_bfd_fetch(fmt, args, ap);
  va_end(ap);
}

struct ld_pad seed_pad(struct ld_pad p, long double y)
{
  struct ld_pad r = p;
  r.x = y;
  r.k = p.k + 1;
  return r;
}

struct ld_one seed_one(struct ld_one o) { return o; }
union ld_mix seed_mix(union ld_mix m) { return m; }

struct ld_pair seed_pair(long double a, struct ld_pair p, long double b)
{
  struct ld_pair r;
  r.a = b;
  r.b = p.a;
  (void) a;
  return r;
}

long double seed_nest(struct ld_nest *n, int which)
{
  struct ld_nest copy = *n;
  if (which == 0) return copy.o.x;
  if (which == 1) return n->m[1].x;
  return (&copy.m[0])->x;
}

long double seed_ternary(int c, long double a, long double b) { return c ? a : b; }

long double seed_cast(long double x)
{
  ld_t y = (long double) x;
  return (ld_t) y;
}

long double seed_array(ld_t *v, int i)
{
  ld_t tmp[3];
  long double *p = tmp;
  tmp[i] = v[i];
  {
    long double y = *(p + i);
    return *&y;
  }
}

/* Initialization copies whole objects, braced or not, at any nesting. */
long seed_init(const long double *v)
{
  long double arr[3] = {v[0], v[1], v[2]};
  long double open[] = {v[4], v[5]};
  long double braced = {v[6]};
  struct ld_pad p = {'i', v[3], 5};
  struct ld_pair pairs[2] = {{v[0], v[1]}, {v[2], v[3]}};
  long bad = 0;
  if (memcmp(&arr[0], &v[0], 10) || memcmp(&arr[1], &v[1], 10) || memcmp(&arr[2], &v[2], 10)) bad |= 1;
  if (sizeof open != 32 || memcmp(&open[0], &v[4], 10) || memcmp(&open[1], &v[5], 10)) bad |= 2;
  if (memcmp(&braced, &v[6], 10)) bad |= 4;
  if (p.c != 'i' || p.k != 5 || memcmp(&p.x, &v[3], 10)) bad |= 8;
  if (memcmp(&pairs[1].a, &v[2], 10) || memcmp(&pairs[1].b, &v[3], 10)) bad |= 16;
  return bad;
}

/* An identifier-list definition: long double has no default promotion. */
long double seed_knr(x, k)
     long double x;
     int k;
{
  return k ? x : x;
}

/* Deliberately unprototyped: the call passes a long double and an int. */
long double host_knr();

/* Forth calls the peer and itself; each result is checked bitwise. */
long seed_outbound(const long double *v)
{
  struct ld_pad p, q;
  struct ld_one o;
  union ld_mix m;
  struct ld_pair pr;
  long double r, (*fp)(long double) = host_id;
  if (!host_same(&v[0], &v[0])) return 100;
  r = host_id(v[1]); if (!host_same(&r, &v[1])) return 101;
  r = fp(v[2]); if (!host_same(&r, &v[2])) return 102;
  r = host_pick(0, v[0], 2.5, v[1], 77, v[2]); if (!host_same(&r, &v[0])) return 103;
  r = host_pick(1, v[0], 2.5, v[1], 77, v[2]); if (!host_same(&r, &v[1])) return 104;
  r = host_pick(2, v[0], 2.5, v[1], 77, v[2]); if (!host_same(&r, &v[2])) return 105;
  r = host_many(1, 2, 3, 4, 5, 6, v[3], 7, v[4]); if (!host_same(&r, &v[3])) return 106;
  r = host_va(2, v[0], v[1], v[2], v[3]); if (!host_same(&r, &v[2])) return 107;
  r = host_va(3, v[4], 1.25, v[5]); if (!host_same(&r, &v[5])) return 108;
  p.c = 'p'; p.x = v[6]; p.k = 41;
  q = host_pad(p, v[5]); if (q.c != 'p' || q.k != 42 || !host_same(&q.x, &v[5])) return 109;
  o.x = v[4]; o = host_one(o); if (!host_same(&o.x, &v[4])) return 110;
  m.x = v[3]; m = host_mix(m); if (!host_same(&m.x, &v[3])) return 111;
  pr.a = v[1]; pr.b = v[2];
  pr = host_pair(v[0], pr, v[6]); if (!host_same(&pr.a, &v[6]) || !host_same(&pr.b, &v[1])) return 112;
  r = seed_id(host_id(seed_id(v[5]))); if (!host_same(&r, &v[5])) return 113;
  r = seed_pick(3, v[0], 2.5, v[1], 77, v[2]); if (!host_same(&r, &v[0])) return 114;
  r = host_va_named(v[0], 0); if (!host_same(&r, &v[0])) return 116;
  r = host_va_named(v[0], 7, 0, v[1], 1, v[2], 2, v[3], 3, v[4], 4, v[5], 5, v[6], 6, v[2]);
  if (!host_same(&r, &v[2])) return 117;
  r = seed_va_named(v[1], 2, 0, v[4], 1, v[5]); if (!host_same(&r, &v[5])) return 118;
  r = host_knr(v[6], 3); if (!host_same(&r, &v[6])) return 115;
  return 0;
}
