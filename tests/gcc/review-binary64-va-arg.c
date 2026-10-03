/* Independent review: list aliases, member arrays, pointer contexts and SSE. */
#include <stdarg.h>

struct item { long value; double next; };
struct list_box { long guard; va_list list; };
union bits { double d; unsigned long u; };
static int selections;

static struct __seed_va_list_tag *select_list(va_list list)
{
    selections += 1;
    return list;
}

static double indirect(struct __seed_va_list_tag **list)
{
    return va_arg(*list, double);
}

int review_contexts(unsigned long first, unsigned long second, ...)
{
    va_list list;
    struct list_box box;
    struct item *ptr;
    struct __seed_va_list_tag *alias;
    double *dp;
    union bits bits;
    unsigned int gp;
    unsigned int fp;
    va_start(list, second);
    box.guard = 0x12345678;
    va_copy(box.list, list);
    gp = list->gp_offset;
    alias = list;
    bits.d = indirect(&alias);
    if (bits.u != first || list->gp_offset != gp) return 1;
    selections = 0;
    bits.d = va_arg(select_list(list), const double);
    if (bits.u != second || selections != 1) return 2;
    fp = list->fp_offset;
    ptr = va_arg(list, struct item *);
    if (ptr->value != 345 || list->fp_offset != fp) return 3;
    if (va_arg(list, struct item *)->value != 678) return 4;
    dp = va_arg(list, double *);
    bits.d = *dp;
    if (bits.u != first || list->fp_offset != fp) return 5;
    if (box.guard != 0x12345678) return 6;
    bits.d = va_arg(box.list, double);
    if (bits.u != first) return 7;
    bits.d = va_arg(box.list, double);
    if (bits.u != second) return 8;
    if (va_arg(box.list, struct item *)->value != 345) return 9;
    va_end(box.list);
    va_end(list);
    return 0;
}

int review_drain(va_list list, const char *shape, const unsigned long *expected)
{
    union bits bits;
    va_list copy;
    unsigned int gp;
    unsigned int fp;
    unsigned long overflow;
    int round;
    int i;
    va_copy(copy, list);
    for (round=0; round<2; ++round) {
        for (i=0; shape[i]; ++i) {
            gp = list->gp_offset;
            fp = list->fp_offset;
            overflow = (unsigned long)list->overflow_arg_area;
            if (overflow & 7) return 11;
            if (shape[i] == 'd') {
                bits.d = va_arg(select_list(list), double);
                if (list->gp_offset != gp) return 12;
                if (list->fp_offset != (fp < 176 ? fp + 16 : fp)) return 13;
                if ((unsigned long)list->overflow_arg_area != overflow + (fp < 176 ? 0 : 8)) return 14;
            } else {
                bits.u = va_arg(list, unsigned long);
                if (list->fp_offset != fp) return 15;
                if (list->gp_offset != (gp < 48 ? gp + 8 : gp)) return 16;
                if ((unsigned long)list->overflow_arg_area != overflow + (gp < 48 ? 0 : 8)) return 17;
            }
            if (bits.u != expected[i]) return 30 + i;
        }
        if (!round) va_copy(list, copy);
    }
    va_end(copy);
    return 0;
}

int review_named8(long a, long b, long c, long d, long e, long f,
                  const char *shape, const unsigned long *want, ...)
{
    va_list list;
    int result;
    va_start(list, want);
    result = review_drain(list, shape, want);
    va_end(list);
    return a+b+c+d+e+f == 21 ? result : 10;
}
