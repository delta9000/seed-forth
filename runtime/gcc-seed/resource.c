/* Original seed-forth implementation; see LICENSE and SYSINFO.md.
   Resource limits, usage, scheduling priority and process times. */
#include <sys/resource.h>
#include <sys/times.h>
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>

static long seed_resource_call(long number, long a1, long a2, long a3)
{
    long result = __seed_syscall6(number, a1, a2, a3, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return result;
}

int getrlimit(int resource, struct rlimit *limit)
{
    return (int)seed_resource_call(97, resource, (long)limit, 0);
}

int setrlimit(int resource, const struct rlimit *limit)
{
    return (int)seed_resource_call(160, resource, (long)limit, 0);
}

int getrusage(int who, struct rusage *usage)
{
    return (int)seed_resource_call(98, who, (long)usage, 0);
}

int getpriority(int which, id_t who)
{
    /* The kernel returns 20 - nice so that its results stay positive. */
    long result = seed_resource_call(140, which, (long)who, 0);
    if (result == -1) return -1;
    return 20 - (int)result;
}

int setpriority(int which, id_t who, int priority)
{
    return (int)seed_resource_call(141, which, (long)who, priority);
}

int nice(int increment)
{
    /* As glibc: the new nice value, with EACCES reported as EPERM. */
    int saved = errno;
    int value;
    errno = 0;
    value = getpriority(PRIO_PROCESS, 0);
    if (value == -1 && errno != 0) return -1;
    if (setpriority(PRIO_PROCESS, 0, value + increment) == -1) {
        if (errno == EACCES) errno = EPERM;
        return -1;
    }
    errno = 0;
    value = getpriority(PRIO_PROCESS, 0);
    if (value == -1 && errno != 0) return -1;
    errno = saved;
    return value;
}

clock_t times(struct tms *buffer)
{
    return (clock_t)seed_resource_call(100, (long)buffer, 0, 0);
}
