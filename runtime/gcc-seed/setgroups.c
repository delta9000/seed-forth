/* Original seed-forth implementation; see LICENSE and PASSWD.md. */
#include <grp.h>
#include <errno.h>
#include <seed-syscall.h>

int setgroups(size_t size, const gid_t *list)
{
    long result = __seed_syscall6(116, (long)size, (long)list, 0, 0, 0, 0);
    if (result < 0 && result >= -4095) { errno = (int)-result; return -1; }
    return 0;
}
