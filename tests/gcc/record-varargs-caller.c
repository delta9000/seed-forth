/* Calls passing records to unprototyped and variadic functions. Every
   result is printed; host GCC builds of either side must agree. */
#include <stdio.h>
#include "record-varargs.h"

static struct X make_x(int seed)
{
    struct X x;
    unsigned char *p = (unsigned char *)&x;
    int i;
    for (i = 0; i < 16; i++)
        p[i] = (unsigned char)(seed * 13 + i * 7);
    p[7] |= 0x80; /* a normal binary80 value: explicit integer bit, */
    p[8] = 0xff;  /* exponent 0x3fff */
    p[9] = 0x3f;
    return x;
}

int main(void)
{
    struct S1 s1 = { 3, -4 }, t1 = { 40, 9 };
    struct S2 s2 = { 1234567890123L, 'q' }, t2 = { -5, 7 };
    struct S3 s3 = { { 'a', 'b', 'c' } };
    struct Big big = { 10, 20, 30 }, other = { -7, 8, -9 };
    union U u;
    struct X x = make_x(1), y = make_x(5);
    long cell = 77;
    long (*fp)() = knr_sum;
    struct S2 (*mp)() = knr_make;
    struct Big r;
    int i;

    for (i = 0; i < 12; i++)
        u.c[i] = (char)(i * 9 + 1);
    u.l = -99;

    printf("knr %ld\n", knr_sum(s1, 2, s2, big));
    printf("knr-pointer %ld\n", fp(t1, -3, t2, other));
    r.x = knr_make(21L).l;
    printf("knr-make %ld %d\n", r.x, mp(5L).c);
    r = empty_make();
    printf("empty %ld %ld %ld\n", r.x, r.y, r.z);
    {
        long proto_sum();
        printf("unprototyped-proto %ld\n", proto_sum(t1, 6L, other));
    }
    printf("short %ld\n", vsum("12", s1, s2));
    printf("mixed %ld\n", vsum("1l2b3iu", s1, 5L, s2, big, s3, 6, u));
    /* Register exhaustion: S2 needs two GP registers when one is left, so it
       goes to the stack; the next one-eightbyte record still uses RSI..R9. */
    printf("exhaust %ld\n", vsum("llll21lb", 1L, 2L, 3L, 4L, s2, t1, 9L, big));
    printf("exhaust-union %ld\n", vsum("lllluiu1", 1L, 2L, 3L, 4L, u, 8, u, s1));
    printf("doubles %ld\n", vsum("d1d2dbdu", 1.25, s1, -2.5, s2, 3.75, big, 0.5, u));
    printf("x87 %ld\n", vsum("x1xl", x, t1, y, 11L));
    printf("pointer %ld\n", vsum("p3p1", &cell, s3, &cell, t1));
    printf("many %ld\n", vsum("1212121212bbuu33", s1, s2, t1, t2, s1, s2, t1, t2,
                             s1, s2, big, other, u, u, s3, s3));
    printf("list %ld\n", vlist("2b1ux3d", s2, other, t1, u, y, s3, 2.0));
    r = vbig(4, big, t2, 1000L);
    printf("vbig %ld %ld %ld\n", r.x, r.y, r.z);
    printf("vnamed %ld\n", vnamed(s2, 3, s1, t1, s1, big));
    printf("vnamed-full %ld\n", vnamed(t2, 6, s1, t1, s1, t1, s1, t1, other));
    return 0;
}
