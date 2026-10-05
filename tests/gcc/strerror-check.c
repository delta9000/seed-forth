/* Prints strerror text for every errno value the runtime defines and for
   unknown numbers; the Forth build must match host glibc byte for byte. */
#include <string.h>
#include <errno.h>
#include <stdio.h>

int main(void)
{
    static const int numbers[] = { 0, EPERM, ENOENT, ESRCH, EINTR, EIO, E2BIG, ENOEXEC,
        EBADF, ECHILD, EAGAIN, ENOMEM, EACCES, EFAULT, EEXIST, ENODEV, ENOTDIR,
        EISDIR, EINVAL, ENFILE, EMFILE, ENOTTY, ENOSPC, ESPIPE, EPIPE, EDOM, ERANGE,
        ENAMETOOLONG, ENOSYS, ENOTEMPTY, ELOOP, EOVERFLOW, EILSEQ, ETIMEDOUT, ESTALE,
        -1, 4096, 99999, -2147483647 - 1 };
    unsigned int i;
    char *text;
    for (i = 0; i < sizeof(numbers) / sizeof(numbers[0]); i++) {
        errno = 4242;
        text = strerror(numbers[i]);
        printf("%d %s %d\n", numbers[i], text, errno == 4242);
    }
    return 0;
}
