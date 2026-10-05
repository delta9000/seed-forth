/* Original seed-forth implementation; see LICENSE and PROCFS.md.
   Linux AMD64 gettimeofday through the raw syscall (no vDSO). */
#include <sys/time.h>
#include <errno.h>
#include <seed-syscall.h>

int gettimeofday(struct timeval *now, void *zone)
{
    long status;
    /* The kernel validates and writes both optional pointers itself. */
    status = __seed_syscall6(96, (long)now, (long)zone, 0, 0, 0, 0);
    if (status < 0 && status >= -4095) {
        errno = (int)-status;
        return -1;
    }
    return 0;
}
