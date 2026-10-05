/* Independent host-only Linux syscall bridge; never production input. */
#include <unistd.h>
#include <errno.h>
long __seed_syscall6(long n, long a, long b, long c, long d, long e, long f)
{
    int saved = errno;
    long result = syscall(n, a, b, c, d, e, f);
    if (result == -1) result = -errno;
    errno = saved;
    return result;
}
