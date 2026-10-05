/* Oracle-only bridge: libc syscall is never a production object input. */
#include <unistd.h>
#include <errno.h>
long mapping_raw(long number, long a, long b, long c, long d, long e, long f)
{
    int saved = errno;
    long result = syscall(number, a, b, c, d, e, f);
    if (result == -1) result = -errno;
    errno = saved;
    return result;
}
long __seed_syscall6(long number, long a, long b, long c, long d, long e, long f)
{
    return mapping_raw(number, a, b, c, d, e, f);
}
