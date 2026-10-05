/* Original seed-forth implementation; see LICENSE. Linux AMD64. */
#include <stdio.h>
#include <errno.h>
#include <seed-syscall.h>
int remove(const char *path)
{
    long result;
    /* Unlink removes the name itself, including a symlink. Only Linux's
       directory error requests rmdir; no stat/follow-symlink precheck. */
    result = __seed_syscall6(87, (long)path, 0, 0, 0, 0, 0);
    if (result == -EISDIR)
        result = __seed_syscall6(84, (long)path, 0, 0, 0, 0, 0);
    if (result < 0) { errno = (int)-result; return -1; }
    return 0;
}
