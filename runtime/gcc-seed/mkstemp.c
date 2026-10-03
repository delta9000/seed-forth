/* Original seed-forth implementation; see LICENSE. Linux AMD64. */
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <seed-syscall.h>
int mkstemp(char *template)
{
    static const char alphabet[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    size_t length = strlen(template);
    unsigned long random;
    unsigned char *bytes = (unsigned char *)&random;
    size_t filled;
    long result;
    int attempt;
    int index;
    if (length < 6 || strcmp(template + length - 6, "XXXXXX")) {
        errno = EINVAL;
        return -1;
    }
    for (attempt = 0; attempt < 128; attempt++) {
        filled = 0;
        while (filled < sizeof(random)) {
            result = __seed_syscall6(318, (long)(bytes + filled),
                                    sizeof(random) - filled, 0, 0, 0, 0);
            if (result == -EINTR) continue;
            if (result <= 0) {
                errno = result < 0 ? (int)-result : EIO;
                goto failed;
            }
            filled += (size_t)result;
        }
        for (index = 0; index < 6; index++) {
            template[length - 6 + index] = alphabet[random % 62UL];
            random /= 62UL;
        }
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
