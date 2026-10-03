#include "varargs-fixture.h"

typedef va_list saved_list;

long seed_vsum(int count, va_list list)
{
    long sum = 0;
    int index;
    for (index = 0; index < count; index = index + 1)
        sum = sum + va_arg(list, long);
    return sum;
}

long seed_sum(int count, ...)
{
    saved_list list;
    long sum;
    va_start(list, count);
    sum = seed_vsum(count, list);
    va_end(list);
    return sum;
}

long seed_named5(long a, long b, long c, long d, long e, ...)
{
    va_list list;
    long result;
    va_start(list, e);
    result = a + b + c + d + e + va_arg(list, long);
    result = result + va_arg(list, long);
    result = result + va_arg(list, long);
    va_end(list);
    return result;
}

long seed_named6(long a, long b, long c, long d, long e, long f, ...)
{
    va_list list;
    long result;
    va_start(list, f);
    result = a + b + c + d + e + f + va_arg(list, long);
    result = result + va_arg(list, long);
    va_end(list);
    return result;
}

long seed_named7(long a, long b, long c, long d, long e, long f, long g, ...)
{
    va_list list;
    long result;
    va_start(list, g);
    result = a + b + c + d + e + f + g + va_arg(list, long);
    result = result + va_arg(list, long);
    va_end(list);
    return result;
}

long seed_promotions(int marker, ...)
{
    va_list list;
    int narrow_char;
    int narrow_short;
    unsigned int high;
    long negative;
    char *pointer;
    unsigned long wide;
    int promoted_uchar;
    int promoted_ushort;
    va_start(list, marker);
    narrow_char = va_arg(list, int);
    narrow_short = va_arg(list, int);
    high = va_arg(list, unsigned int);
    negative = va_arg(list, long);
    pointer = va_arg(list, char *);
    wide = va_arg(list, unsigned long);
    promoted_uchar = va_arg(list, int);
    promoted_ushort = va_arg(list, int);
    va_end(list);
    if (narrow_char != -7 || narrow_short != -300 || high != 4294967295U)
        return 1;
    if (negative != -5000000000L || pointer[0] != 'v' || wide != 18446744073709551615UL)
        return 2;
    if (promoted_uchar != 255 || promoted_ushort != 65535) return 3;
    return marker;
}

long seed_copy(int count, ...)
{
    va_list original;
    saved_list copied;
    saved_list second;
    long left;
    long right;
    int index;
    va_start(original, count);
    index = 0;
    va_copy(copied, (index = index + 1, original));
    if (index != 1) return -3;
    left = seed_vsum(count, original);
    right = seed_vsum(count, copied);
    va_end(copied);
    va_end(original);
    if (left != right) return -1;
    va_start(original, count);
    for (index = 0; index < 4; index = index + 1) va_arg(original, long);
    __va_copy(second, original);
    left = seed_vsum(count - 4, original);
    right = seed_vsum(count - 4, second);
    va_end(second);
    va_end(original);
    if (left != right) return -2;
    return left;
}

long seed_recursive(int depth, ...)
{
    va_list list;
    long result;
    va_start(list, depth);
    result = va_arg(list, long);
    if (depth > 0)
        result = result + seed_recursive(depth - 1, 10L, 20L, 30L, 40L, 50L, 60L);
    result = result + seed_vsum(5, list);
    va_end(list);
    return result;
}

long seed_callback(long (*consumer)(int, va_list), int count, ...)
{
    va_list list;
    long result;
    va_start(list, count);
    result = consumer(count, list);
    va_end(list);
    return result;
}

int seed_layout(int marker, ...)
{
    va_list list;
    saved_list copy;
    char *base;
    va_start(list, marker);
    base = (char *)list;
    if (sizeof(va_list) != 24 || sizeof(list) != 24 || sizeof(copy) != 24)
        return 1;
    if ((char *)&list[0].gp_offset - base != 0) return 2;
    if ((char *)&list[0].fp_offset - base != 4) return 3;
    if ((char *)&list[0].overflow_arg_area - base != 8) return 4;
    if ((char *)&list[0].reg_save_area - base != 16) return 5;
    if (list[0].gp_offset != 8 || list[0].fp_offset != 48) return 6;
    if (sizeof(va_arg(list, long)) != 8 || list[0].gp_offset != 8) return 7;
    va_end(list);
    return 0;
}

long seed_apply(int marker, ...)
{
    va_list list;
    seed_unary function;
    long value;
    va_start(list, marker);
    function = va_arg(list, seed_unary);
    value = va_arg(list, long);
    va_end(list);
    return function(value);
}
