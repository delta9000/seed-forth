/* Left shifts of negative and overflowing signed values in integer constant
   expressions, folded as two's complement as GCC does: static initializers,
   case labels, array bounds and enumerators, through coreutils' macros. */
#include <stdio.h>
#define TYPE_SIGNED(t) (! ((t) 0 < (t) -1))
#define TYPE_MINIMUM(t) ((t) (TYPE_SIGNED (t) \
                              ? ~ (t) 0 << (sizeof (t) * 8 - 1) \
                              : (t) 0))
#define TYPE_MAXIMUM(t) ((t) (~ (t) 0 - TYPE_MINIMUM (t)))

static long x = -1L << 3;
static long long_min = TYPE_MINIMUM (long), long_max = TYPE_MAXIMUM (long);
static int int_min = TYPE_MINIMUM (int), int_max = TYPE_MAXIMUM (int);
static short short_min = TYPE_MINIMUM (short), short_max = TYPE_MAXIMUM (short);
static long long llong_min = TYPE_MINIMUM (long long);
static unsigned long ulong_min = TYPE_MINIMUM (unsigned long), ulong_max = TYPE_MAXIMUM (unsigned long);
static int wrap = 3 << 30, sign = 1 << 31, high = 0x40000000 << 1;
static long table[] = { -1L << 62, -5L << 60, 7L << 61 };
static char bound[(-1 << 2) + 6];
enum { MINUS_FOUR = -1 << 2, INT_MINIMUM = TYPE_MINIMUM (int), SHORTS = (short) -1 << 15 };

static const char *label(int value)
{
    switch (value) {
    case (-1 << 2): return "minus-four";
    case TYPE_MINIMUM (int): return "int-minimum";
    case (-3 << 4): return "minus-forty-eight";
    default: return "other";
    }
}

int main(void)
{
    printf("x %ld\n", x);
    printf("long %ld %ld\n", long_min, long_max);
    printf("int %d %d\n", int_min, int_max);
    printf("short %d %d\n", short_min, short_max);
    printf("llong %lld\n", llong_min);
    printf("ulong %lu %lu\n", ulong_min, ulong_max);
    printf("wrap %d %d %d\n", wrap, sign, high);
    printf("table %ld %ld %ld\n", table[0], table[1], table[2]);
    printf("bound %d\n", (int)sizeof bound);
    printf("enum %d %d %d\n", MINUS_FOUR, INT_MINIMUM, SHORTS);
    printf("case %s %s %s %s\n", label(-4), label(int_min), label(-48), label(4));
    return 0;
}
