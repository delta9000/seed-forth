/* Driver for the original libiberty strtoll/strtoull objects. */
#include <errno.h>
#include <stdio.h>

long long strtoll(const char *, char **, int);
unsigned long long strtoull(const char *, char **, int);

int main(void)
{
    static const char *const inputs[] = {
        "9223372036854775807", "-9223372036854775808", "9223372036854775808",
        "-12345", "  +0x7fffffffffffffff", "18446744073709551615",
        "18446744073709551616", "077", "-1", "zz", 0
    };
    static const int bases[] = { 0, 10, 16, 36 };
    int i, b;
    char *end;
    for (b = 0; b < 4; b++)
        for (i = 0; inputs[i]; i++) {
            long long s;
            unsigned long long u;
            int es;
            errno = 0;
            s = strtoll(inputs[i], &end, bases[b]);
            es = errno;
            errno = 0;
            u = strtoull(inputs[i], &end, bases[b]);
            printf("%d %s %lld %d %llu %d %d\n", bases[b], inputs[i], s, es, u, errno,
                   (int)(end - inputs[i]));
        }
    return 0;
}
