/* Original seed-forth implementation; see LICENSE and FILE-CALLS.md. */
#include <sys/time.h>
#include <errno.h>
#include <seed-syscall.h>

int utimes(const char *path, const struct timeval times[2])
{
    /* struct timeval has the kernel's two-long layout (syscall 235). */
    long result = __seed_syscall6(235, (long)path, (long)times, 0, 0, 0, 0);
    if (result < 0 && result >= -4095) { errno = (int)-result; return -1; }
    return 0;
}
