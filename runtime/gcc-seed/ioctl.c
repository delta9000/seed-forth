/* Original seed-forth implementation; see LICENSE and TERMIOS.md. */
#include <sys/ioctl.h>
#include <stdarg.h>
#include <errno.h>
#include <seed-syscall.h>

int ioctl(int descriptor, unsigned long request, ...)
{
    /* One optional argument, forwarded as the full register value like
       glibc; requests without an argument ignore it. */
    va_list arguments;
    void *argument;
    long result;
    va_start(arguments, request);
    argument = va_arg(arguments, void *);
    va_end(arguments);
    result = __seed_syscall6(16, descriptor, (long)request, (long)argument, 0, 0, 0);
    if (result < 0 && result >= -4095) { errno = (int)-result; return -1; }
    return (int)result;
}
