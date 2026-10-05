/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <errno.h>
#include <string.h>

/* One message per error number declared in <errno.h>, worded as Linux
   reports them so diagnostics read the same as on a conventional system. */
static const struct {
    int number;
    const char *text;
} strerror_table[] = {
    {EPERM, "Operation not permitted"},
    {ENOENT, "No such file or directory"},
    {EINTR, "Interrupted system call"},
    {EIO, "Input/output error"},
    {E2BIG, "Argument list too long"},
    {EBADF, "Bad file descriptor"},
    {EAGAIN, "Resource temporarily unavailable"},
    {ENOMEM, "Cannot allocate memory"},
    {EACCES, "Permission denied"},
    {EFAULT, "Bad address"},
    {EEXIST, "File exists"},
    {ENOTDIR, "Not a directory"},
    {EISDIR, "Is a directory"},
    {EINVAL, "Invalid argument"},
    {ENFILE, "Too many open files in system"},
    {EMFILE, "Too many open files"},
    {ENOTTY, "Inappropriate ioctl for device"},
    {ENOSPC, "No space left on device"},
    {ESPIPE, "Illegal seek"},
    {EPIPE, "Broken pipe"},
    {EDOM, "Numerical argument out of domain"},
    {ERANGE, "Numerical result out of range"},
    {ENAMETOOLONG, "File name too long"},
    {ENOSYS, "Function not implemented"},
    {ENOTEMPTY, "Directory not empty"},
    {ELOOP, "Too many levels of symbolic links"},
    {EOVERFLOW, "Value too large for defined data type"},
    {EILSEQ, "Invalid or incomplete multibyte or wide character"},
    {0, "Success"}
};

/* "Unknown error " plus a signed decimal int fits in 14 + 11 + 1 bytes. */
static char strerror_unknown[32];

char *strerror(int error)
{
    static const char prefix[] = "Unknown error ";
    char digits[12];
    unsigned long magnitude;
    size_t i;
    size_t length = 0;
    size_t count = sizeof strerror_table / sizeof strerror_table[0];
    for (i = 0; i < count; i = i + 1)
        if (strerror_table[i].number == error)
            return (char *)strerror_table[i].text;
    for (i = 0; prefix[i] != 0; i = i + 1)
        strerror_unknown[length++] = prefix[i];
    if (error < 0) {
        strerror_unknown[length++] = '-';
        magnitude = (unsigned long)(-(long)error);
    } else {
        magnitude = (unsigned long)error;
    }
    i = 0;
    do {
        digits[i++] = (char)('0' + magnitude % 10);
        magnitude = magnitude / 10;
    } while (magnitude != 0);
    while (i != 0)
        strerror_unknown[length++] = digits[--i];
    strerror_unknown[length] = 0;
    return strerror_unknown;
}
