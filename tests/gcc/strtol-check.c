/* strtol cases; Forth runtime and host libc must print identical lines. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

static const char *const inputs[] = {
    "0", "1", "-1", "+42", "  \t\n\v\f\r-17xyz", "9223372036854775807",
    "9223372036854775808", "-9223372036854775808", "-9223372036854775809",
    "99999999999999999999999", "-99999999999999999999999", "0x7fffffffffffffff",
    "-0x8000000000000000", "0X1g", "0x", "0xz", "077", "-0777", "08", "z",
    "Zz", "-", "+", "", "   ", "1010", "-zzzzzzzzzzzzz", "zzzzzzzzzzzzzz"
};
static const int bases[] = {0, 2, 8, 10, 16, 36, 1, 37};

int main(void)
{
    unsigned i, j;
    for (i = 0; i < sizeof inputs / sizeof inputs[0]; i++)
        for (j = 0; j < sizeof bases / sizeof bases[0]; j++) {
            char *end;
            long value;
            errno = 0;
            value = strtol(inputs[i], &end, bases[j]);
            /* ISO C leaves the end pointer unspecified for an invalid base. */
            printf("%u base %d -> %ld end %ld errno %d\n", i, bases[j], value,
                   bases[j] == 1 || bases[j] == 37 ? -1L : (long)(end - inputs[i]), errno);
        }
    errno = 0;
    printf("null end %ld errno %d\n", strtol("-12", 0, 10), errno);
    return 0;
}
