/* Forth-built renamed copy isolates forced raw-syscall results from production. */
#include <sys/time.h>
#include <errno.h>
#include <stdio.h>
int tested_gettimeofday(struct timeval *, void *);
static long result, number, args[6];
static int calls;
long tested_timeofday_syscall(long n, long a, long b, long c, long d, long e, long f)
{
    ++calls;
    number = n;
    args[0] = a; args[1] = b; args[2] = c;
    args[3] = d; args[4] = e; args[5] = f;
    return result;
}
static void prepare(long value)
{
    result = value;
    calls = 0;
    number = -1;
    errno = 777;
}
static int sent(void *now, void *zone)
{
    return calls == 1 && number == 96 && args[0] == (long)now && args[1] == (long)zone
        && args[2] == 0 && args[3] == 0 && args[4] == 0 && args[5] == 0;
}
int main(void)
{
    struct timeval value;
    int zone[2];
    long code;
    /* Both pointers are forwarded unchanged, NULL included. */
    prepare(0);
    if (tested_gettimeofday(&value, 0) != 0 || !sent(&value, 0) || errno != 777) return 1;
    prepare(0);
    if (tested_gettimeofday(0, zone) != 0 || !sent(0, zone) || errno != 777) return 2;
    /* The whole Linux error window maps to -1 and the positive errno. */
    for (code = -4095; code <= -1; code++) {
        prepare(code);
        if (tested_gettimeofday(&value, zone) != -1 || errno != (int)-code || !sent(&value, zone))
            return 3;
    }
    /* Values outside the window are not errors. */
    prepare(-4096);
    if (tested_gettimeofday(&value, 0) != 0 || errno != 777) return 4;
    prepare(5);
    if (tested_gettimeofday(&value, 0) != 0 || errno != 777) return 5;
    printf("timeofday fault contracts passed\n");
    return 0;
}
