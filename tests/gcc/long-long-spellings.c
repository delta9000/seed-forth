/* Accepted long long spellings, __extension__ positions and conversions. */
#include <limits.h>

/* Every spelling of one type redeclares the same object compatibly. */
long long int a1; signed long long a1; long signed long int a1; int long long a1;
unsigned long long b1; long long unsigned int b1; long unsigned long b1;
unsigned long int long b1;
long long c_fn(long long);
signed long long int c_fn(long int long x) { return x - 1; }
unsigned long long d_fn(unsigned long long (*f)(long long), long long v);
static unsigned long long twice(long long v) { return (unsigned long long)v * 2; }
unsigned long long d_fn(long long unsigned (*f)(long long int), long long v) { return f(v); }

__extension__ long long ext_global = __extension__ 5LL;
__extension__ typedef unsigned long long ext_u;
struct ext_s { __extension__ long long m; char c; };
static const long long const_table[] = { LLONG_MAX, -LLONG_MAX, (long long)ULLONG_MAX };

int main(void)
{
    __extension__ long long local = 3;
    long long *pl = &a1;
    unsigned long long *pu = &b1;
    const volatile long long cv = -9;
    register long long r = 11;
    ext_u u = (ext_u)-1;
    struct ext_s s;
    s.m = __extension__ (local + 1);
    if (sizeof(struct ext_s) != 16 || sizeof(const_table) != 24) return 1;
    if ((long long)(signed char)-1 != -1LL) return 2;
    if ((unsigned long long)(unsigned)-1 != 4294967295ULL) return 3;
    if (c_fn(LLONG_MIN + 1) != LLONG_MIN) return 4;
    if (ext_global + s.m != 9) return 5;
    if (sizeof(long long int) != 8 || sizeof(unsigned long long) != 8) return 6;
    if (*pl != 0 || *pu != 0) return 7;
    if (d_fn(twice, -4) != (unsigned long long)-8) return 8;
    if (cv + r != 2 || u != ULLONG_MAX || const_table[2] != -1) return 9;
    if (sizeof(cv + 1u) != 8 || sizeof((char)1 + 1LL) != 8) return 10;
    if (!(r > -1LL) || (u > 0LL) != 1 || (-1LL > 0ULL) == 0) return 11;
    if (-LLONG_MAX - 1 != LLONG_MIN || (LLONG_MAX >> 62) != 1) return 12;
    return 42;
}
