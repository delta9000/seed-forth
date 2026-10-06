/* Original seed-forth implementation; see LICENSE and TERMIOS.md.
   The terminal's name from /proc/self/fd, checked against the device. */
#include <unistd.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
#include <seed-syscall.h>

static int seed_ttyname(int descriptor, char *buffer, size_t size)
{
    char link[32], name[PATH_MAX];
    long attributes[8];
    struct stat device, named;
    long result;
    ssize_t length;
    int digits = 0, index;
    unsigned int value = (unsigned int)descriptor;
    char reversed[12];
    /* TCGETS fails with ENOTTY (or EBADF) unless this is a terminal. */
    result = __seed_syscall6(16, descriptor, TCGETS, (long)attributes, 0, 0, 0);
    if (result < 0) return (int)-result;
    if (fstat(descriptor, &device) < 0) return errno;
    memcpy(link, "/proc/self/fd/", 14);
    do {
        reversed[digits++] = (char)('0' + value % 10);
        value /= 10;
    } while (value);
    for (index = 0; index < digits; index++) link[14 + index] = reversed[digits - 1 - index];
    link[14 + digits] = '\0';
    length = readlink(link, name, sizeof(name) - 1);
    if (length < 0) return errno == ENOENT ? EBADF : errno;
    name[length] = '\0';
    /* The link may name a device seen through another mount namespace. */
    if (stat(name, &named) < 0 || named.st_rdev != device.st_rdev
        || named.st_ino != device.st_ino) return ENODEV;
    if ((size_t)length + 1 > size) return ERANGE;
    memcpy(buffer, name, (size_t)length + 1);
    return 0;
}

/* The error number is returned and, as glibc does, also left in errno. */
int ttyname_r(int descriptor, char *buffer, size_t size)
{
    int error = seed_ttyname(descriptor, buffer, size);
    if (error) errno = error;
    return error;
}

char *ttyname(int descriptor)
{
    static char name[PATH_MAX];
    int error = ttyname_r(descriptor, name, sizeof(name));
    if (error) {
        errno = error;
        return NULL;
    }
    return name;
}
