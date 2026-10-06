/* Original seed-forth implementation; see LICENSE and FILE-CALLS.md. */
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>

static int seed_dup_call(long number, long a1, long a2, long a3)
{
    long result = __seed_syscall6(number, a1, a2, a3, 0, 0, 0);
    if (result < 0 && result >= -4095) { errno = (int)-result; return -1; }
    return (int)result;
}

/* Unlike dup2, equal descriptors fail with EINVAL (Linux dup3). */
int dup3(int descriptor, int target, int flags)
{
    return seed_dup_call(292, descriptor, target, flags);
}

int pipe2(int descriptors[2], int flags)
{
    return seed_dup_call(293, (long)descriptors, flags, 0);
}
