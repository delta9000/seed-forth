/* Caller side: prints every observed value with printf's ll conversions. */
#include <limits.h>
#include <stdio.h>
#include "long-long.h"

static const long long ll_values[] = {
    0LL, 1LL, -1LL, 7LL, -7LL, 2147483647LL, -2147483647LL - 1,
    4294967296LL, -4294967296LL, LLONG_MAX, LLONG_MIN, LLONG_MIN + 1
};
static const ull_t ull_values[] = {
    0ULL, 1uLL, 3ull, 4294967295LLU, 4294967296llu, 0x8000000000000000ULL, ULLONG_MAX
};
#define COUNT(a) (int)(sizeof(a) / sizeof((a)[0]))

int main(void)
{
    int i, j, s;
    long long signed int x;
    long unsigned long y;
    struct ll_pair pair;
    struct ll_bits bits;
    long l = -3;
    unsigned long ul = 5;

    printf("layout");
    for (i = 0; ll_layout[i]; i++) printf(" %d", ll_layout[i]);
    printf("\nglobals %lld %lld %lld %lld %llu %llx\n", ll_table[0], ll_table[1],
           ll_table[2], ll_table[3], ull_global, ull_global);
    printf("limits %lld %lld %llu %llX %llo\n", LLONG_MIN, LLONG_MAX, ULLONG_MAX,
           ULLONG_MAX, ULLONG_MAX);
    printf("format [%5lld] [%-6lld] [%+lld] [%020lld] [%#llx] [%.3llu]\n",
           -42LL, 42LL, 42LL, LLONG_MIN, 255ULL, 7ULL);
    for (i = 0; i < COUNT(ll_values); i++)
        for (j = 0; j < COUNT(ll_values); j++) {
            long long a = ll_values[i], b = ll_values[j];
            printf("ll %lld %lld: %lld %d", a, b,
                   (long long)((unsigned long long)ll_add(a, b)), ll_less(a, b));
            if (b != 0 && !(a == LLONG_MIN && b == -1))
                printf(" %lld %lld", ll_div(a, b), ll_mod(a, b));
            printf(" %llu %llu\n", ull_mix((long)a, (unsigned long long)b),
                   ll_mix(a, (unsigned long)b));
        }
    for (i = 0; i < COUNT(ull_values); i++)
        for (j = 0; j < COUNT(ull_values); j++) {
            ull_t a = ull_values[i], b = ull_values[j];
            printf("ull %llu %llu: %d", a, b, ull_less(a, b));
            if (b) printf(" %llu %llu", ull_div(a, b), ull_mod(a, b));
            printf("\n");
        }
    for (s = 0; s < 64; s++)
        printf("shift %d %lld %lld %llu %llx\n", s, ll_shl(1, s), ll_sar(LLONG_MIN, s),
               ull_shr(ULLONG_MAX, s), 1ULL << s);
    /* Usual arithmetic conversions: long long ranks above long. */
    printf("mixed %llu %llu %lld %d %d %d %d\n", l + 1ULL, 2LL + ul,
           -5LL + 3U, -1LL < 0U, -1LL < 0UL, l < 1ULL, (int)sizeof(l + 1LL));
    printf("varargs %lld %llx %lld\n",
           ll_sum(9, 1LL, -2LL, LLONG_MAX, LLONG_MIN, 5LL, 6LL, 7LL, 8LL, -9LL),
           ull_xor(8, 1ULL, ULLONG_MAX, 3ULL, 0x8000000000000000ULL, 5ULL, 6ULL, 7ULL, 8ULL),
           ll_sum(0));
    printf("many %lld\n", ll_many(1, LLONG_MAX, -3, 4, LLONG_MIN, 6, 7, -8));
    pair = ll_pair_make(LLONG_MIN + 5, ULLONG_MAX - 4);
    printf("pair %d %lld %llu %lld\n", pair.tag, pair.a, pair.b, ll_pair_total(&pair));
    for (i = 0; i < COUNT(ll_values); i++)
        printf("double %llx %lld %llx\n", ll_double_bits(ll_values[i]),
               ll_from_double((double)ll_values[i] / 4.0), ull_double_bits(ll_values[i]));
    printf("udouble %llx %llu %llu %llu\n", ull_double_bits(ULLONG_MAX),
           ull_from_double(9223372036854775808.0), ull_from_double(1e19),
           ull_from_double(4294967296.5));
    x = ll_narrow(0x123456789abcdefLL);
    y = (unsigned long long)ll_narrow(-0x123456789abcdefLL);
    printf("narrow %lld %llu %lld %lld\n", x, y, ll_widen(-2, 4294967295U, -3, 255),
           ll_widen(INT_MIN, 0U, 32767, 0));
    x = ll_bits_read(&bits, 0xffffffffffULL, -1LL);
    printf("bits %lld %llx %lld %d\n", x, (unsigned long long)bits.low,
           (long long)bits.high, bits.rest);
    printf("switch %d %d %d %d %d\n", ll_switch(0x100000000LL), ll_switch(-4294967296LL),
           ll_switch(LLONG_MIN), ll_switch(LLONG_MAX), ll_switch(13));
    x = 5; x *= 3; x -= 20; x <<= 33; x >>= 1; x /= 3; x %= 1000000007;
    y = 5; y--; ++y; y = ~y; y ^= 0xffULL; y |= 1; y &= ~2ULL;
    printf("assign %lld %llx %d %d\n", x, y, !x, x ? 1 : 0);
    return 0;
}
