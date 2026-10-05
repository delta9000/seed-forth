/* Original seed-forth implementation; see LICENSE and PROCESS-API.md.
   Error text for the errno values this runtime defines (Linux C locale). */
#include <string.h>
#include <stdio.h>
#include <errno.h>

struct seed_error_text {
    int number;
    const char *text;
};

static const struct seed_error_text seed_error_texts[] = {
    { 0, "Success" }, { EPERM, "Operation not permitted" },
    { ENOENT, "No such file or directory" }, { ESRCH, "No such process" },
    { EINTR, "Interrupted system call" }, { EIO, "Input/output error" },
    { E2BIG, "Argument list too long" }, { ENOEXEC, "Exec format error" },
    { EBADF, "Bad file descriptor" }, { ECHILD, "No child processes" },
    { EAGAIN, "Resource temporarily unavailable" },
    { ENOMEM, "Cannot allocate memory" }, { EACCES, "Permission denied" },
    { EFAULT, "Bad address" }, { EEXIST, "File exists" },
    { ENODEV, "No such device" }, { ENOTDIR, "Not a directory" },
    { EISDIR, "Is a directory" }, { EINVAL, "Invalid argument" },
    { ENFILE, "Too many open files in system" }, { EMFILE, "Too many open files" },
    { ENOTTY, "Inappropriate ioctl for device" },
    { ENOSPC, "No space left on device" }, { ESPIPE, "Illegal seek" },
    { EPIPE, "Broken pipe" }, { EDOM, "Numerical argument out of domain" },
    { ERANGE, "Numerical result out of range" },
    { ENAMETOOLONG, "File name too long" }, { ENOSYS, "Function not implemented" },
    { ENOTEMPTY, "Directory not empty" },
    { ELOOP, "Too many levels of symbolic links" },
    { EOVERFLOW, "Value too large for defined data type" },
    { EILSEQ, "Invalid or incomplete multibyte or wide character" },
    { ETIMEDOUT, "Connection timed out" }, { ESTALE, "Stale file handle" }
};

char *strerror(int number)
{
    /* Single-threaded: the unknown-number text is overwritten by the next
       unknown lookup. Known texts are constant and must not be modified. */
    static char unknown[32];
    unsigned int i;
    int saved = errno;
    for (i = 0; i < sizeof(seed_error_texts) / sizeof(seed_error_texts[0]); i++)
        if (seed_error_texts[i].number == number) return (char *)seed_error_texts[i].text;
    snprintf(unknown, sizeof(unknown), "Unknown error %d", number);
    errno = saved;
    return unknown;
}
