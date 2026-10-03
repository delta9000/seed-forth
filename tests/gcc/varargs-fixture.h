#ifndef SEED_VARARGS_FIXTURE_H
#define SEED_VARARGS_FIXTURE_H
#include <stdarg.h>
typedef long (*seed_unary)(long value);
long seed_apply(int marker, ...);
long seed_sum(int count, ...);
long seed_vsum(int count, va_list list);
long seed_named5(long a, long b, long c, long d, long e, ...);
long seed_named6(long a, long b, long c, long d, long e, long f, ...);
long seed_named7(long a, long b, long c, long d, long e, long f, long g, ...);
long seed_promotions(int marker, ...);
long seed_copy(int count, ...);
long seed_recursive(int depth, ...);
long seed_callback(long (*consumer)(int, va_list), int count, ...);
int seed_layout(int marker, ...);
#endif
