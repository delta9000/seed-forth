/* Original seed-forth implementation; see LICENSE. Single-threaded Linux. */
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>
int unlink(const char *path)
{
    long result = __seed_syscall6(87, (long)path, 0, 0, 0, 0, 0);
    if (result < 0) { errno = (int)-result; return -1; }
    return 0;
}
void _exit(int status)
{
    for (;;) __seed_syscall6(60, (long)(status & 255), 0, 0, 0, 0, 0);
}
