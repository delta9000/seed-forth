/* Original seed-forth implementation; see LICENSE and FCNTL.md.
   Bounded Linux AMD64 fcntl: descriptor flags, status flags, duplication. */
#include <fcntl.h>
#include <stdarg.h>
#include <errno.h>
#include <seed-syscall.h>

int fcntl(int descriptor, int command, ...)
{
    va_list arguments;
    int argument = 0;
    long result;
    switch (command) {
    case F_GETFD:
    case F_GETFL:
        /* No third argument is read; callers may omit it or pass anything. */
        break;
    case F_DUPFD:
    case F_DUPFD_CLOEXEC:
    case F_SETFD:
    case F_SETFL:
        va_start(arguments, command);
        argument = va_arg(arguments, int);
        va_end(arguments);
        break;
    default:
        /* Locks, ownership, leases, pipe sizes and seals are not provided. */
        errno = EINVAL;
        return -1;
    }
    result = __seed_syscall6(72, descriptor, command, argument, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return (int)result;
}
