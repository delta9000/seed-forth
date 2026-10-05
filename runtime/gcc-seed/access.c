/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>

int access(const char *path, int mode)
{
    /* Linux access uses real IDs and validates mode/path itself. Do not turn
       this check into an open, use effective IDs, or inspect user memory. */
    long result = __seed_syscall6(21, (long)path, (long)mode, 0, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return (int)result;
}
