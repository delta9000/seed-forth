/* This file uses the host's stdarg.h/libc only as an interoperability oracle.
   Its object and executable never enter a production reconstruction. */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include "varargs-fixture.h"

int seed_format(char *, unsigned long, const char *, ...);
long seed_call_host(void);

long host_vsum(int count, va_list list)
{
    long sum = 0;
    int index;
    for (index = 0; index < count; ++index) sum += va_arg(list, long);
    return sum;
}

long host_sum(int count, ...)
{
    va_list list;
    long result;
    va_start(list, count);
    result = host_vsum(count, list);
    va_end(list);
    return result;
}

static long host_forward(int count, ...)
{
    va_list list;
    long result;
    va_start(list, count);
    result = seed_vsum(count, list);
    va_end(list);
    return result;
}

static long triple(long value) { return value * 3; }

int main(void)
{
    float floating_single;
    double floating_double;
    long double floating_extended;
    char actual[128];
    char expected[128];
    const char *format = "%d:%u:%ld:%s:%p:%lu";
    char small = -7;
    short medium = -300;
    unsigned char small_unsigned = 255;
    unsigned short medium_unsigned = 65535;
    int written;
    if (seed_sum(0) != 0 || seed_sum(1, -91L) != -91L) return 1;
    if (seed_sum(5, 1L, 2L, 3L, 4L, 5L) != 15) return 2;
    if (seed_sum(6, 1L, 2L, 3L, 4L, 5L, 6L) != 21) return 3;
    if (seed_sum(10, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L, 9L, 10L) != 55) return 4;
    if (seed_named5(1, 2, 3, 4, 5, 6L, 7L, 8L) != 36) return 5;
    if (seed_named6(1, 2, 3, 4, 5, 6, 7L, 8L) != 36) return 6;
    if (seed_named7(1, 2, 3, 4, 5, 6, 7, 8L, 9L) != 45) return 7;
    if (seed_promotions(77, small, medium, 4294967295U, -5000000000L,
                        "variadic", 18446744073709551615UL, small_unsigned, medium_unsigned) != 77) return 8;
    if (seed_copy(8, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L) != 26) return 9;
    if (seed_recursive(3, 10L, 20L, 30L, 40L, 50L, 60L) != 840) return 10;
    if (seed_callback(host_vsum, 7, 1L, 2L, 3L, 4L, 5L, 6L, 7L) != 28) return 11;
    if (host_forward(8, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L) != 36) return 12;
    if (seed_call_host() != 5) return 13;
    if (seed_layout(0) != 0) return 14;
    written = seed_format(actual, sizeof actual, format, -7, 4294967295U,
                          -5000000000L, "variadic", (void *)actual,
                          18446744073709551615UL);
    if (snprintf(expected, sizeof expected, format, -7, 4294967295U,
                 -5000000000L, "variadic", (void *)actual,
                 18446744073709551615UL) != written) return 15;
    if (strcmp(actual, expected) != 0) return 16;
    if (seed_apply(0, triple, 14L) != 42) return 17;
    if (!seed_float_pointers(&floating_single, &floating_double, &floating_extended,
                             &floating_single, &floating_double, &floating_extended)) return 18;
    return 0;
}
