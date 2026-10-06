/* _Bool conversions, promotions, storage, bitfields, static initializers
   and calls. Every value is printed; host GCC must print the same bytes. */
#include <stdio.h>
#include <stddef.h>
#include "bool.h"

static _Bool s_int = 256, s_half = 0.5, s_negzero = -0.0, s_cast = (_Bool)7, s_zero = 0;
static _Bool s_tiny = 1e-300, s_float = 0.25f, s_neg = -1, s_null = (_Bool)(char *)0;
static struct bits s_bits = { 3, 2, 5, 0, 9 };
static _Bool s_array[4] = { 2, 0, -3, 1 };
enum { E_TRUE = (_Bool)42, E_SIZE = sizeof(_Bool) };

static int sum(int n) { return n; }

int main(void)
{
    _Bool b = 256, ok = true, cell;
    bool c = false;
    long big = 1L << 40;
    unsigned u = 0xffffffffu;
    double nan = 0.0 / 0.0, negzero = -0.0, inf = 1.0 / 0.0;
    float f = 0.25f, fz = 0.0f;
    char *p = 0, *q = (char *)&b;
    int (*fp)(int) = sum;
    struct bits x = { 1, 1, 15, 1, 1 };
    struct flags fl = { 1, 1, 4, 1, 16, 1 };
    _Bool arr[3] = { 2, 0, 3 };
    int i;

    printf("init %d %d %d size %d %d %d defined %d\n", b, ok, c, (int)sizeof(_Bool),
           (int)sizeof(bool), (int)sizeof arr, __bool_true_false_are_defined);
    printf("layout %d %d %d %d %d %d\n", (int)sizeof(struct flags), (int)offsetof(struct flags, b),
           (int)offsetof(struct flags, t), (int)offsetof(struct flags, u),
           (int)sizeof(struct bits), (int)sizeof(s_array));
    b = big; printf("big %d\n", b);
    b = u + 1; printf("wrap %d\n", b);
    b = u; printf("unsigned %d\n", b);
    b = nan; printf("nan %d\n", b);
    b = negzero; printf("negzero %d\n", b);
    b = inf; printf("inf %d\n", b);
    b = f; printf("float %d\n", b);
    b = fz; printf("float-zero %d\n", b);
    b = p; printf("null %d\n", b);
    b = q; printf("pointer %d\n", b);
    b = fp; printf("function %d %d\n", b, (_Bool)fp);
    b = 0; b++; b++; printf("increment %d\n", b);
    b = 0; b--; printf("decrement %d\n", b);
    b = 1; b--; printf("decrement-one %d\n", b);
    b = 1; b += 4; printf("add %d\n", b);
    b = 1; b -= 1; printf("subtract %d\n", b);
    b = 1; b *= 2; printf("multiply %d\n", b);
    b = 2 > 1; c = !b; printf("compare %d %d\n", b, c);
    printf("promote %d %d %d %d %d\n", ok + ok, -ok, ~ok, ok << 4, (int)sizeof(ok + ok));
    printf("casts %d %d %d %d\n", (_Bool)0.0, (_Bool)-1, (_Bool)(char *)8, (int)(_Bool)0x100);
    printf("static %d %d %d %d %d %d %d %d %d\n", s_int, s_half, s_negzero, s_cast, s_zero,
           s_tiny, s_float, s_neg, s_null);
    printf("static-array %d %d %d %d enum %d %d\n", s_array[0], s_array[1], s_array[2], s_array[3],
           E_TRUE, E_SIZE);
    printf("bits %d %d %d %d %d\n", x.a, x.b, x.c, x.d, x.e);
    printf("static-bits %d %d %d %d %d\n", s_bits.a, s_bits.b, s_bits.c, s_bits.d, s_bits.e);
    x.b = 4; x.d = 0; x.e++; printf("bits-store %d %d %d %d %d\n", x.a, x.b, x.c, x.d, x.e);
    printf("array %d %d %d\n", arr[0], arr[1], arr[2]);
    switch (ok) { case 0: puts("switch 0"); break; case 1: puts("switch 1"); break; }
    printf("calls %d %d %d %d %d %d\n", bool_from_long(1L << 33), bool_from_long(0),
           bool_from_long(-1), bool_from_double(1e-310), bool_from_double(0.0 / 0.0),
           bool_from_double(-0.0));
    printf("pointer-calls %d %d\n", bool_from_pointer(&b), bool_from_pointer(0));
    printf("take %d %d\n", bool_take(5, 0, 7, 0.5), bool_take(0, -2, -1, 0));
    printf("record %d\n", bool_flags(fl));
    for (i = 0; i < 5; i++) {
        struct bits r = bool_bits(i);
        printf("bits-call %d: %d %d %d %d %d\n", i, r.a, r.b, r.c, r.d, r.e);
    }
    i = bool_store(&cell, 1L << 50);
    printf("store %d %d", i, cell);
    i = bool_store(&cell, 0);
    printf(" %d %d\n", i, cell);
    return !ok;
}
