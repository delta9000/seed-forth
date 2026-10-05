/* Case labels at every depth of a switch body convert to the promoted
   controlling type (C90 6.6.4.2).  Built by the Forth driver and by host
   GCC; both programs must print the same lines.  */
#include <stdio.h>

/* The reviewer's reproduction: a nested -1 label on unsigned int.  */
static int review(void)
{
    unsigned int x = 4294967295U;
    switch (x) { if (1) { case -1: return 0; } }
    return 1;
}

/* Depth 0, 1, 2 and 3 labels on unsigned int.  */
static int depths(unsigned int x)
{
    int r = 0;
    switch (x) {
    case -1: r = 10; break;
        if (x) {
        case -2: r = 20; break;
            while (r < 100) {
            case -3: r = 30; break;
                {
                    do {
                    case -4: r = 40; break;
                    } while (0);
                }
            }
        }
    default: r = 99;
    }
    return r;
}

/* Out-of-range labels on int: converted (truncated) like the scrutinee.  */
static int truncate_int(int x)
{
    switch (x) {
        if (1) {
        case 4294967296LL + 5: return 5;
            {
            case 4294967295LL: return -1;
            }
        }
    case 2147483648U: return 7;
    }
    return 0;
}

/* Signed char, unsigned short and unsigned char promote to int.  */
static int narrow(signed char c, unsigned short s, unsigned char u)
{
    int r = 0;
    switch (c) { { case -1: r += 1; } }
    switch (s) { if (1) { case 65535: r += 10; } }
    switch (u) { { { case 255: r += 100; } } }
    return r;
}

/* long long and unsigned long long scrutinees keep 64-bit labels.  */
static int wide(long long ll, unsigned long long ull)
{
    int r = 0;
    switch (ll) {
        if (1) { case -1: r += 1; break; }
        { case 4294967295LL: r += 2; break; }
        { { case -4294967296LL: r += 4; break; } }
    }
    switch (ull) {
        while (1) { case -1: r += 8; break; }
        if (0) { case 4294967295U: r += 16; }
        break;
        { case -2LL: r += 32; }
    }
    return r;
}

/* unsigned long: a nested -1 label is the all-ones 64-bit value, while an
   int-valued label 4294967295 stays distinct.  */
static int ulong_labels(unsigned long x)
{
    switch (x) {
        if (x) { case -1: return 1; }
        { case 4294967295U: return 2; }
    }
    return 0;
}

/* A nested default and a case inside a nested switch belong to the
   innermost open switch.  */
static int inner(unsigned int a, long long b)
{
    switch (a) {
        if (1) {
        case -1:
            switch (b) {
                { case -1: return 1; }
            default: return 2;
            }
        }
        { default: return 3; }
    }
    return 4;
}

int main(void)
{
    unsigned int i;
    printf("review %d\n", review());
    for (i = 0; i < 6; i++)
        printf("depths %u %d\n", i, depths(-(int)i));
    printf("truncate %d %d %d %d\n", truncate_int(5), truncate_int(-1),
           truncate_int(-2147483647 - 1), truncate_int(3));
    printf("narrow %d %d\n", narrow(-1, 65535, 255), narrow(1, 1, 1));
    printf("wide %d %d %d %d %d\n", wide(-1, -1), wide(4294967295LL, 4294967295U),
           wide(-4294967296LL, -2), wide(0, 0), wide(-1, 4294967295U));
    printf("ulong %d %d %d\n", ulong_labels(-1), ulong_labels(4294967295U),
           ulong_labels(5));
    printf("inner %d %d %d\n", inner(-1, -1), inner(-1, 7), inner(3, -1));
    return 0;
}
