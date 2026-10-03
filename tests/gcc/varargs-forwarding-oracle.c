/* Host-only checks of opaque floating argument preservation. */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include "varargs-fixture.h"

int seed_format(char *, unsigned long, const char *, ...);
long seed_forward_reenter(int depth, ...);
long seed_forward_named7(long, long, long, long, long, long, long, ...);
long host_al_upper_bound(void);

static long host_vcount(int count, va_list list)
{
    int index;
    long sum = 0;
    if ((unsigned long)list[0].reg_save_area & 15UL) return -1;
    for (index = 1; index <= count; ++index) {
        double value = va_arg(list, double);
        if (value != index) return -1;
        sum += (long)value;
    }
    return sum;
}

/* GCC generates AL=0..8 here; counts9 and10 also enter the overflow area.
   The callback+count named parameters require an alignment padding slot. */
static long pass_by_count(int count)
{
    switch (count) {
    case 0: return seed_callback(host_vcount, 0);
    case 1: return seed_callback(host_vcount, 1, 1.0);
    case 2: return seed_callback(host_vcount, 2, 1.0, 2.0);
    case 3: return seed_callback(host_vcount, 3, 1.0, 2.0, 3.0);
    case 4: return seed_callback(host_vcount, 4, 1.0, 2.0, 3.0, 4.0);
    case 5: return seed_callback(host_vcount, 5, 1.0, 2.0, 3.0, 4.0, 5.0);
    case 6: return seed_callback(host_vcount, 6, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0);
    case 7: return seed_callback(host_vcount, 7, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0);
    case 8: return seed_callback(host_vcount, 8, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0);
    case 9: return seed_callback(host_vcount, 9, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0);
    default: return seed_callback(host_vcount, 10, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0);
    }
}

long host_vsequence(int depth, va_list list)
{
    int index;
    for (index = 1; index <= 10; ++index) {
        if (va_arg(list, double) != depth + index + 0.25) return -1;
        if (va_arg(list, long) != depth * 100 + index) return -1;
    }
    if (va_arg(list, long double) != depth + 0.5L) return -1;
    return depth + 1;
}

long host_reenter(int depth)
{
    return seed_forward_reenter(depth,
        depth + 1.25, depth * 100 + 1L, depth + 2.25, depth * 100 + 2L,
        depth + 3.25, depth * 100 + 3L, depth + 4.25, depth * 100 + 4L,
        depth + 5.25, depth * 100 + 5L, depth + 6.25, depth * 100 + 6L,
        depth + 7.25, depth * 100 + 7L, depth + 8.25, depth * 100 + 8L,
        depth + 9.25, depth * 100 + 9L, depth + 10.25, depth * 100 + 10L,
        depth + 0.5L);
}

long host_vnamed7(va_list list)
{
    int index;
    if (va_arg(list, long) != 91L) return -1000;
    for (index = 1; index <= 10; ++index)
        if (va_arg(list, double) != index + 0.5) return -1000;
    if (va_arg(list, long double) != 42.25L) return -1000;
    if (va_arg(list, long) != 92L) return -1000;
    return 100;
}

int host_forwarding_checks(void)
{
    char actual[512];
    char expected[512];
    const char *format = "%a:%ld:%a:%ld:%a:%ld:%a:%ld:%a:%ld:"
                         "%a:%ld:%a:%ld:%a:%ld:%a:%ld:%a:%ld:%La";
    int actual_count;
    int expected_count;
    int count;
    /* Floating extras may be ignored while independent GP slots are read. */
    if (seed_sum(0, 1.25) != 0) return 1;
    if (seed_sum(2, 11L, 1.25, 22L, 2.5) != 33) return 2;
    for (count = 0; count <= 10; ++count)
        if (pass_by_count(count) != count * (count + 1) / 2) return 3;
    if (host_reenter(3) != 10) return 4;
    if (seed_forward_named7(1, 2, 3, 4, 5, 6, 7, 91L,
            1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 10.5,
            42.25L, 92L) != 128) return 5;
    actual_count = seed_format(actual, sizeof actual, format,
        1.25, 11L, 2.25, 22L, 3.25, 33L, 4.25, 44L, 5.25, 55L,
        6.25, 66L, 7.25, 77L, 8.25, 88L, 9.25, 99L, 10.25, 110L, 42.5L);
    expected_count = snprintf(expected, sizeof expected, format,
        1.25, 11L, 2.25, 22L, 3.25, 33L, 4.25, 44L, 5.25, 55L,
        6.25, 66L, 7.25, 77L, 8.25, 88L, 9.25, 99L, 10.25, 110L, 42.5L);
    if (actual_count != expected_count || strcmp(actual, expected)) return 6;
    if (host_al_upper_bound() != 73) return 7;
    return 0;
}
