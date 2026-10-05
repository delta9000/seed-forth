/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>

char *getcwd(char *buffer, size_t size)
{
    long result;
    /* Caller storage only: GNU allocating NULL-buffer forms are unsupported. */
    if (buffer == NULL || size == 0) { errno = EINVAL; return NULL; }
    result = __seed_syscall6(79, (long)buffer, (long)size, 0, 0, 0, 0);
    if (result < 0 && result >= -4095) {
        errno = (int)-result;
        return NULL;
    }
    /* Linux reports a NUL-inclusive length, or an error without truncation.
       Reject its special non-absolute "(unreachable)" result. No getwd or
       directory-walk fallback is supplied for paths beyond kernel PATH_MAX. */
    if (buffer[0] != '/') { errno = ENOENT; return NULL; }
    return buffer;
}
