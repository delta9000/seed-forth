/* Original seed-forth implementation; see LICENSE and DESCRIPTOR-IO.md.
   Bounded public descriptor I/O for Linux AMD64, without FILE bookkeeping. */
#include <fcntl.h>
#include <unistd.h>
#include <stdarg.h>
#include <errno.h>
#include <seed-syscall.h>

int open(const char *path, int flags, ...)
{
    mode_t mode = 0;
    va_list arguments;
    long result;
    int supported = O_ACCMODE | O_CREAT | O_EXCL | O_NOCTTY | O_TRUNC
        | O_APPEND | O_NONBLOCK | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        | O_PATH | O_TMPFILE;
    /* Reject unsupported bits before inspecting optional arguments. A lone
       Linux __O_TMPFILE bit is invalid, not a request to fetch absent mode. */
    if ((flags & ~supported) || (flags & O_ACCMODE) == O_ACCMODE
        || ((flags & 4194304) && (flags & O_TMPFILE) != O_TMPFILE)) {
        errno = EINVAL;
        return -1;
    }
    if ((flags & O_CREAT) || (flags & O_TMPFILE) == O_TMPFILE) {
        va_start(arguments, flags);
        mode = va_arg(arguments, mode_t);
        va_end(arguments);
    }
    result = __seed_syscall6(2, (long)path, flags, mode, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return (int)result;
}

ssize_t read(int descriptor, void *bytes, size_t count)
{
    long result = __seed_syscall6(0, descriptor, (long)bytes, (long)count, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return (ssize_t)result;
}

int close(int descriptor)
{
    long result = __seed_syscall6(3, descriptor, 0, 0, 0, 0, 0);
    /* Linux may release the descriptor even when reporting EINTR or an I/O
       failure. Retrying could close an unrelated, newly reused descriptor. */
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return -1;
    }
    return (int)result;
}

off_t lseek(int descriptor, off_t offset, int whence)
{
    long result = __seed_syscall6(8, descriptor, offset, whence, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return (off_t)-1;
    }
    return (off_t)result;
}
