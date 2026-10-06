/* Original seed-forth implementation; see LICENSE and FILE-CALLS.md. */
#include <sys/file.h>
#include <errno.h>
#include <seed-syscall.h>

int flock(int descriptor, int operation)
{
    long result = __seed_syscall6(73, descriptor, operation, 0, 0, 0, 0);
    if (result < 0 && result >= -4095) { errno = (int)-result; return -1; }
    return 0;
}
