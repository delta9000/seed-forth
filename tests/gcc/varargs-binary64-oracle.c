/* Independent host callers, including host-created lists consumed by Forth. */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

int seed_f64_consume(va_list, const char *, const unsigned long *);
int seed_f64_check(const char *, const unsigned long *, int, ...);
int seed_f64_named7(long, long, long, long, long,
                    const char *, const unsigned long *, ...);
double seed_f64_return(int, ...);
int seed_f64_overflow_copy(const unsigned long *, ...);

static unsigned long bits(double value)
{
    unsigned long result;
    memcpy(&result, &value, sizeof result);
    return result;
}

static int host_list(const char *shape, const unsigned long *expected, ...)
{
    va_list list;
    int result;
    va_start(list, expected);
    result = seed_f64_consume(list, shape, expected);
    va_end(list);
    return result;
}

static int host_named_double(double named, const char *shape,
                              const unsigned long *expected, ...)
{
    va_list list;
    int result;
    if (named != 99.5) return 800;
    va_start(list, expected);
    result = seed_f64_consume(list, shape, expected);
    va_end(list);
    return result;
}

int host_f64_reenter(int depth)
{
    unsigned long want[24];
    int i;
    for (i = 0; i < 12; ++i) {
        want[2*i] = bits((double)i + 0.5);
        want[2*i+1] = (unsigned long)(101+i);
    }
    return seed_f64_check("dldldldldldldldldldldldl", want, depth,
        0.5,101UL,1.5,102UL,2.5,103UL,3.5,104UL,4.5,105UL,5.5,106UL,
        6.5,107UL,7.5,108UL,8.5,109UL,9.5,110UL,10.5,111UL,11.5,112UL);
}

int main(void)
{
    unsigned long w[24];
    unsigned long special[] = {0x8000000000000000UL,0x7ff0000000000000UL,
        0xfff0000000000000UL,0x7ff8123456789abcUL,1UL};
    double values[5];
    int i, result;
#define CHECK(call) do { result = (call); if (result) { \
    fprintf(stderr, "line %d: result %d\n", __LINE__, result); return 1; } } while (0)
    CHECK(host_f64_reenter(4));
    for (i=0;i<12;++i) w[i]=bits((double)i+0.5);
    CHECK(seed_f64_check("dddddddddddd",w,0,
        0.5,1.5,2.5,3.5,4.5,5.5,6.5,7.5,8.5,9.5,10.5,11.5));
    CHECK(host_list("dddddddddddd",w,
        0.5,1.5,2.5,3.5,4.5,5.5,6.5,7.5,8.5,9.5,10.5,11.5));
    CHECK(host_named_double(99.5,"dddddddddddd",w,
        0.5,1.5,2.5,3.5,4.5,5.5,6.5,7.5,8.5,9.5,10.5,11.5));
    for (i=0;i<12;++i) { w[i]=101UL+i; w[12+i]=bits((double)i+0.5); }
    CHECK(seed_f64_check("lllllllllllldddddddddddd",w,0,
        101UL,102UL,103UL,104UL,105UL,106UL,107UL,108UL,109UL,110UL,111UL,112UL,
        0.5,1.5,2.5,3.5,4.5,5.5,6.5,7.5,8.5,9.5,10.5,11.5));
    for (i=0;i<12;++i) { w[i]=bits((double)i+0.5); w[12+i]=101UL+i; }
    CHECK(seed_f64_check("ddddddddddddllllllllllll",w,0,
        0.5,1.5,2.5,3.5,4.5,5.5,6.5,7.5,8.5,9.5,10.5,11.5,
        101UL,102UL,103UL,104UL,105UL,106UL,107UL,108UL,109UL,110UL,111UL,112UL));
    for (i=0;i<12;++i) { w[2*i]=bits((double)i+0.5); w[2*i+1]=101UL+i; }
    CHECK(seed_f64_named7(1L,2L,3L,4L,5L,"dldldldldldldldldldldldl",w,
        0.5,101UL,1.5,102UL,2.5,103UL,3.5,104UL,4.5,105UL,5.5,106UL,
        6.5,107UL,7.5,108UL,8.5,109UL,9.5,110UL,10.5,111UL,11.5,112UL));
    CHECK(seed_f64_overflow_copy(w+18,
        0.5,101UL,1.5,102UL,2.5,103UL,3.5,104UL,4.5,105UL,5.5,106UL,
        6.5,107UL,7.5,108UL,8.5,109UL,9.5,110UL,10.5,111UL,11.5,112UL));
    for (i=0;i<5;++i) memcpy(&values[i],&special[i],8);
    CHECK(seed_f64_check("ddddd",special,0,values[0],values[1],values[2],values[3],values[4]));
    if (bits(seed_f64_return(0,values[3])) != special[3]) return 2;
    puts("PASS: binary64 va_arg mixed banks, exhaustion, nested callbacks, copying and host lists");
    return 0;
}
