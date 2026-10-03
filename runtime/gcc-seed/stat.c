/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <sys/stat.h>
#include <errno.h>
#include <seed-syscall.h>

static int seed_stat_result(long result)
{
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return (int)result;
}

int stat(const char *path, struct stat *status)
{
    return seed_stat_result(__seed_syscall6(4, (long)path, (long)status,
                                           0, 0, 0, 0));
}

int fstat(int descriptor, struct stat *status)
{
    return seed_stat_result(__seed_syscall6(5, (long)descriptor, (long)status,
                                           0, 0, 0, 0));
}
