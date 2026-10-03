/* Forth-built callees. No floating argument is emitted by this compiler. */
#include <stdarg.h>

union double_bits { double value; unsigned long bits; };

int seed_f64_consume(va_list list, const char *shape,
                     const unsigned long *expected)
{
    int i;
    unsigned int gp;
    unsigned int fp;
    void *overflow;
    union double_bits actual;
    for (i = 0; shape[i]; ++i) {
        gp = list->gp_offset;
        fp = list->fp_offset;
        overflow = list->overflow_arg_area;
        if (shape[i] == 'd') {
            actual.value = va_arg(list, double);
            if (list->gp_offset != gp) return 1;
            if (fp < 176) {
                if (list->fp_offset != fp + 16) return 2;
                if (list->overflow_arg_area != overflow) return 3;
            } else {
                if (list->fp_offset != fp) return 4;
                if (list->overflow_arg_area != (char *)overflow + 8) return 5;
            }
        } else {
            actual.bits = va_arg(list, unsigned long);
            if (list->fp_offset != fp) return 6;
            if (gp < 48) {
                if (list->gp_offset != gp + 8) return 7;
                if (list->overflow_arg_area != overflow) return 8;
            } else {
                if (list->gp_offset != gp) return 9;
                if (list->overflow_arg_area != (char *)overflow + 8) return 10;
            }
        }
        if (actual.bits != expected[i]) return 11 + i;
    }
    return 0;
}

int host_f64_reenter(int depth);

int seed_f64_check(const char *shape, const unsigned long *expected,
                   int depth, ...)
{
    va_list list;
    va_list saved;
    va_list tail;
    union double_bits first;
    int result;
    unsigned int gp;
    unsigned int fp;
    void *overflow;
    va_start(list, depth);
    if (list->gp_offset != 24 || list->fp_offset != 48) return 100;
    va_copy(saved, list);
    if (depth > 0 && host_f64_reenter(depth - 1)) return 101;
    result = seed_f64_consume(list, shape, expected);
    if (result) return 200 + result;
    if (saved->gp_offset != 24 || saved->fp_offset != 48) return 102;
    result = seed_f64_consume(saved, shape, expected);
    if (result) return 300 + result;
    gp = list->gp_offset;
    fp = list->fp_offset;
    overflow = list->overflow_arg_area;
    va_end(list);
    if (gp != list->gp_offset || fp != list->fp_offset ||
        overflow != list->overflow_arg_area) return 103;
    va_start(list, depth);
    if (shape[0] == 'd') first.value = va_arg(list, double);
    else first.bits = va_arg(list, unsigned long);
    if (first.bits != expected[0]) return 104;
    va_copy(tail, list);
    result = seed_f64_consume(tail, shape + 1, expected + 1);
    if (result) return 400 + result;
    result = seed_f64_consume(list, shape + 1, expected + 1);
    if (result) return 500 + result;
    va_end(tail);
    va_end(saved);
    va_end(list);
    return 0;
}

int seed_f64_named7(long a, long b, long c, long d, long e,
                     const char *shape, const unsigned long *expected, ...)
{
    va_list list;
    int result;
    va_start(list, expected);
    if (list->gp_offset != 48 || list->fp_offset != 48) return 600;
    result = seed_f64_consume(list, shape, expected);
    va_end(list);
    if (a + b + c + d + e != 15) return 601;
    return result;
}

double seed_f64_return(int ignored, ...)
{
    va_list list;
    double result;
    va_start(list, ignored);
    result = va_arg(list, double);
    va_end(list);
    return result;
}

int seed_f64_overflow_copy(const unsigned long *expected, ...)
{
    va_list list;
    va_list copied;
    int i;
    int result;
    va_start(list, expected);
    for (i = 0; i < 9; ++i) {
        (void)va_arg(list, double);
        (void)va_arg(list, unsigned long);
    }
    if (list->gp_offset != 48 || list->fp_offset != 176) return 700;
    va_copy(copied, list);
    result = seed_f64_consume(list, "dldldl", expected);
    if (result) return 710 + result;
    result = seed_f64_consume(copied, "dldldl", expected);
    va_end(copied);
    va_end(list);
    return result;
}
