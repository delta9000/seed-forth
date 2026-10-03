#include "varargs-fixture.h"
int list_parameter_size(va_list list) { return sizeof(list); }
long triple(long value) { return value * 3; }
int main(void)
{
    float floating_single;
    double floating_double;
    long double floating_extended;
    long (*sum)(int, ...) = seed_sum;
    va_list uninitialized;
    char small = -7;
    short medium = -300;
    unsigned char small_unsigned = 255;
    unsigned short medium_unsigned = 65535;
    if (seed_sum(0) != 0) return 1;
    if (seed_sum(1, -91L) != -91L) return 2;
    if (seed_sum(5, 1L, 2L, 3L, 4L, 5L) != 15) return 3;
    if (seed_sum(6, 1L, 2L, 3L, 4L, 5L, 6L) != 21) return 4;
    if (sum(10, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L, 9L, 10L) != 55) return 5;
    if (seed_named5(1, 2, 3, 4, 5, 6L, 7L, 8L) != 36) return 6;
    if (seed_named6(1, 2, 3, 4, 5, 6, 7L, 8L) != 36) return 7;
    if (seed_named7(1, 2, 3, 4, 5, 6, 7, 8L, 9L) != 45) return 8;
    if (seed_promotions(77, small, medium, 4294967295U, -5000000000L,
                        "variadic", 18446744073709551615UL, small_unsigned, medium_unsigned) != 77) return 9;
    if (seed_copy(8, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L) != 26) return 10;
    if (seed_recursive(3, 10L, 20L, 30L, 40L, 50L, 60L) != 840) return 11;
    if (seed_callback(seed_vsum, 7, 1L, 2L, 3L, 4L, 5L, 6L, 7L) != 28) return 12;
    if (seed_layout(0) != 0) return 13;
    if (seed_apply(0, triple, 14L) != 42) return 14;
    if (list_parameter_size(uninitialized) != 8) return 15;
    if (!seed_float_pointers(&floating_single, &floating_double, &floating_extended,
                             &floating_single, &floating_double, &floating_extended)) return 16;
    return 0;
}
