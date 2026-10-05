/* Original seed-forth implementation; see LICENSE. POSIX write on Linux AMD64. */
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>
ssize_t write(int descriptor, const void *bytes, size_t count)
{
    long result = __seed_syscall6(1, descriptor, (long)bytes, (long)count, 0, 0, 0);
    if (result < 0) { errno = (int)-result; return -1; }
    return (ssize_t)result;
}
