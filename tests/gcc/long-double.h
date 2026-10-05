#ifndef LONG_DOUBLE_H
#define LONG_DOUBLE_H
/* Long double data movement shared by Forth-built and host-built units.
   Every value is created by host arithmetic or explicit bytes and checked
   by comparing its ten significant x87 bytes. */
struct ld_pad { char c; long double x; int k; };        /* 48 bytes: MEMORY */
struct ld_one { long double x; };                        /* 16 bytes: X87 */
union ld_mix { int i; long double x; char z[3]; };       /* X87+INTEGER: MEMORY */
struct ld_pair { long double a, b; };                    /* 32 bytes: MEMORY */
struct ld_nest { int n; struct ld_one o; union ld_mix m[2]; char t; };
/* The shape of binutils 2.30 bfd.c's union _bfd_doprnt_args. */
union ld_bfd_args {
  int i; long l; long long ll; double d; long double ld; void *p;
  enum { Bad, Int, Long, LongLong, Double, LongDouble, Ptr } type;
};
typedef long double ld_t;

long seed_layout(long *out);
long double seed_id(long double x);
long double seed_pick(int k, long double a, double d, long double b, long g, long double c);
long double seed_many(long a, long b, long c, long d, long e, long f, long double x, long g, long double y);
long double seed_va(int n, ...);
long double seed_va_named(long double a, int n, ...);
void seed_va_list(long double *out, int n, ...);
void seed_bfd(const char *fmt, union ld_bfd_args *args, ...);
struct ld_pad seed_pad(struct ld_pad p, long double y);
struct ld_one seed_one(struct ld_one o);
union ld_mix seed_mix(union ld_mix m);
struct ld_pair seed_pair(long double a, struct ld_pair p, long double b);
long double seed_nest(struct ld_nest *n, int which);
long double seed_ternary(int c, long double a, long double b);
long seed_outbound(const long double *v);
long double seed_cast(long double x);
long double seed_array(ld_t *v, int i);
long double seed_knr(long double x, int k);
long seed_init(const long double *v);

long double host_id(long double x);
long double host_pick(int k, long double a, double d, long double b, long g, long double c);
long double host_many(long a, long b, long c, long d, long e, long f, long double x, long g, long double y);
long double host_va(int n, ...);
long double host_va_named(long double a, int n, ...);
struct ld_pad host_pad(struct ld_pad p, long double y);
struct ld_one host_one(struct ld_one o);
union ld_mix host_mix(union ld_mix m);
struct ld_pair host_pair(long double a, struct ld_pair p, long double b);
int host_same(const long double *a, const long double *b);
#endif
