/* Original seed-forth implementation; see LICENSE and FILE-CALLS.md. */
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>

int ftruncate(int descriptor, off_t length)
{
    long result = __seed_syscall6(77, descriptor, (long)length, 0, 0, 0, 0);
    if (result < 0 && result >= -4095) { errno = (int)-result; return -1; }
    return 0;
}
