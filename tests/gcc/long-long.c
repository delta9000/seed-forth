/* Provider side: long long arithmetic, conversions, varargs and layout. */
#include <limits.h>
#include <stdarg.h>
#include "long-long.h"

#if !defined(LLONG_MAX) || LLONG_MAX != 0x7fffffffffffffffLL
#error "LLONG_MAX"
#endif
#if ULLONG_MAX != 18446744073709551615ULL || -1LL >= 0
#error "ULLONG_MAX"
#endif

long long ll_table[4] = { LLONG_MIN, LLONG_MAX, -1LL, 0x100000000LL * 3 };
unsigned long long ull_global = ULLONG_MAX - (ULLONG_MAX >> 1);
/* Layout facts become bytes, so every builder reports the same values. */
const char ll_layout[] = {
    (char)sizeof(long long), (char)sizeof(unsigned long long int),
    (char)sizeof(struct ll_pair), (char)sizeof(1LL), (char)sizeof(1ull),
    (char)sizeof(ll_table), (char)sizeof(struct ll_bits),
    (char)(sizeof(long long) == sizeof(long)), 0
};
static char ll_negative_check[(-1LL < 0U) && !(-1LL < 0UL) ? 1 : -1];

long long ll_add(long long a, long long b) { return a + b; }
unsigned long long ull_mix(long a, unsigned long long b) { return a + b; }
unsigned long long ll_mix(long long a, unsigned long b) { return a * b - b; }
long long ll_div(long long a, long long b) { return a / b; }
long long ll_mod(long long a, long long b) { return a % b; }
unsigned long long ull_div(unsigned long long a, unsigned long long b) { return a / b; }
unsigned long long ull_mod(unsigned long long a, unsigned long long b) { return a % b; }
long long ll_shl(long long a, int s) { return (long long)((unsigned long long)a << s); }
long long ll_sar(long long a, int s) { return a >> s; }
unsigned long long ull_shr(unsigned long long a, int s) { return a >> s; }
int ll_less(long long a, long long b) { return (a < b) + 2 * (a <= b) + 4 * (a > b) + 8 * (a >= b); }
int ull_less(unsigned long long a, unsigned long long b) { return (a < b) + 2 * (a <= b) + 4 * (a > b) + 8 * (a >= b); }

long long ll_sum(int count, ...)
{
    va_list ap;
    long long total = 0;
    va_start(ap, count);
    while (count-- > 0) total += va_arg(ap, long long);
    va_end(ap);
    return total;
}

unsigned long long ull_xor(int count, ...)
{
    va_list ap;
    unsigned long long total = 0;
    va_start(ap, count);
    while (count-- > 0) total = (total << 1 | total >> 63) ^ va_arg(ap, unsigned long long);
    va_end(ap);
    return total;
}

long long ll_many(long long a, long long b, long long c, long long d,
                  long long e, long long f, long long g, long long h)
{
    return a - b + c - d + e - f + g * 3 - h * 5;
}

long long ll_pair_total(const struct ll_pair *p) { return p->a + (long long)p->b + p->tag; }

struct ll_pair ll_pair_make(long long a, unsigned long long b)
{
    struct ll_pair p;
    p.tag = 7;
    p.a = a;
    p.b = b;
    return p;
}

static unsigned long long ll_bits_of(double d)
{
    union { double d; unsigned long long u; } v;
    v.d = d;
    return v.u;
}
unsigned long long ll_double_bits(long long a) { return ll_bits_of((double)a); }
unsigned long long ull_double_bits(unsigned long long a) { return ll_bits_of(a); }
long long ll_from_double(double d) { return (long long)d; }
unsigned long long ull_from_double(double d) { return (unsigned long long)d; }

long long ll_narrow(long long a)
{
    signed char c = (signed char)a;
    short s = (short)a;
    int i = (int)a;
    unsigned u = (unsigned)a;
    return c + s + i + (long long)u;
}

long long ll_widen(int i, unsigned u, short s, unsigned char c)
{
    long long a = i, b = u, d = s;
    unsigned long long e = i;
    return a + b + d + c + (long long)(e >> 32);
}

long long ll_bits_read(struct ll_bits *b, unsigned long long low, long long high)
{
    b->low = low;
    b->high = high;
    b->rest = -1;
    return (long long)b->low + b->high;
}

int ll_switch(long long a)
{
    switch (a) {
    case 0x100000000LL: return 1;
    case -0x100000000LL: return 2;
    case LLONG_MIN: return 3;
    case LLONG_MAX: return 4;
    default: return (int)(a & 7);
    }
}
