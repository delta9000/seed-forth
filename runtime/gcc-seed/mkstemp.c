/* Original seed-forth implementation; see LICENSE. Linux AMD64. */
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <seed-syscall.h>

/* Replace the six bytes at NAME with getrandom-chosen letters and digits.
   Returns 0, or -1 with errno from the kernel (EIO for an empty read). */
static int seed_temp_fill(char *name)
{
    static const char alphabet[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    unsigned long random;
    unsigned char *bytes = (unsigned char *)&random;
    size_t filled = 0;
    long result;
    int index;
    while (filled < sizeof(random)) {
        result = __seed_syscall6(318, (long)(bytes + filled),
                                sizeof(random) - filled, 0, 0, 0, 0);
        if (result == -EINTR) continue;
        if (result <= 0) {
            errno = result < 0 ? (int)-result : EIO;
            return -1;
        }
        filled += (size_t)result;
    }
    for (index = 0; index < 6; index++) {
        name[index] = alphabet[random % 62UL];
        random /= 62UL;
    }
    return 0;
}

static int seed_temp_template(const char *template, size_t *length)
{
    *length = strlen(template);
    if (*length < 6 || strcmp(template + *length - 6, "XXXXXX")) {
        errno = EINVAL;
        return -1;
    }
    return 0;
}

int mkstemp(char *template)
{
    size_t length;
    long result;
    int attempt;
    int index;
    if (seed_temp_template(template, &length)) return -1;
    for (attempt = 0; attempt < 128; attempt++) {
        if (seed_temp_fill(template + length - 6)) goto failed;
        do {
            result = __seed_syscall6(2, (long)template, O_RDWR | O_CREAT | O_EXCL,
                                    0600, 0, 0, 0);
        } while (result == -EINTR);
        if (result >= 0) return (int)result;
        if (result != -EEXIST) { errno = (int)-result; goto failed; }
    }
    errno = EEXIST;
failed:
    for (index = 0; index < 6; index++) template[length - 6 + index] = 'X';
    return -1;
}

/* A name is free when lstat reports ENOENT; success preserves errno and any
   other lstat error ends the search with that errno. Another process may
   still create the name first: binutils follows mktemp with mkdir, which
   then fails. */
char *mktemp(char *template)
{
    struct stat status;
    size_t length;
    int attempt;
    int saved = errno;
    if (seed_temp_template(template, &length)) {
        template[0] = '\0';
        return template;
    }
    for (attempt = 0; attempt < 128; attempt++) {
        if (seed_temp_fill(template + length - 6)) break;
        if (lstat(template, &status) != 0) {
            if (errno == ENOENT) { errno = saved; return template; }
            break;
        }
        errno = EEXIST;
    }
    template[0] = '\0';
    return template;
}
