/* Original seed-forth implementation; see LICENSE and SYSINFO.md. */
#include <sys/utsname.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <seed-syscall.h>

int uname(struct utsname *name)
{
    long result = __seed_syscall6(63, (long)name, 0, 0, 0, 0, 0);
    if (result < 0 && result >= -4095) { errno = (int)-result; return -1; }
    return 0;
}

int gethostname(char *name, size_t size)
{
    /* As glibc: the node name, failing ENAMETOOLONG if it and its NUL do
       not fit (the bytes that fit are still copied). */
    struct utsname system;
    size_t length;
    if (uname(&system) < 0) return -1;
    length = strlen(system.nodename) + 1;
    if (length > size) {
        memcpy(name, system.nodename, size);
        errno = ENAMETOOLONG;
        return -1;
    }
    memcpy(name, system.nodename, length);
    return 0;
}
