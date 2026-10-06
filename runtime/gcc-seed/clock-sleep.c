/* Original seed-forth implementation; see LICENSE and SYSINFO.md.
   POSIX clocks, nanosleep, usleep and settimeofday. */
#include <time.h>
#include <sys/time.h>
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>

static int seed_clock_call(long number, long a1, long a2)
{
    long result = __seed_syscall6(number, a1, a2, 0, 0, 0, 0);
    if (result < 0 && result >= -4095) { errno = (int)-result; return -1; }
    return 0;
}

int clock_gettime(clockid_t clock, struct timespec *now)
{
    return seed_clock_call(228, clock, (long)now);
}

int clock_getres(clockid_t clock, struct timespec *resolution)
{
    return seed_clock_call(229, clock, (long)resolution);
}

int nanosleep(const struct timespec *request, struct timespec *remaining)
{
    return seed_clock_call(35, (long)request, (long)remaining);
}

int usleep(useconds_t microseconds)
{
    struct timespec request;
    request.tv_sec = (time_t)(microseconds / 1000000U);
    request.tv_nsec = (long)(microseconds % 1000000U) * 1000L;
    return nanosleep(&request, NULL);
}

int settimeofday(const struct timeval *now, const struct timezone *zone)
{
    return seed_clock_call(164, (long)now, (long)zone);
}
