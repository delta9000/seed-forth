/* Original seed-forth implementation; see LICENSE. Fixed ASCII C locale.
 * The defined-input contract matches atol. Overflow saturates with ERANGE,
 * the same explicit extension used by the bounded atoi implementation. */
#include <stdlib.h>
#include <ctype.h>
#include <limits.h>
#include <errno.h>

long atol(const char *text)
{
    unsigned long value = 0;
    unsigned long limit;
    unsigned long digit;
    int negative = 0;
    int overflow = 0;
    while (isspace((unsigned char)*text)) text++;
    if (*text == '+' || *text == '-') { negative = *text == '-'; text++; }
    limit = (unsigned long)LONG_MAX + (unsigned long)negative;
    while (*text >= '0' && *text <= '9') {
        digit = (unsigned long)(*text++ - '0');
        if (value > limit / 10UL || (value == limit / 10UL && digit > limit % 10UL))
            overflow = 1;
        if (!overflow) value = value * 10UL + digit;
    }
    if (overflow) { errno = ERANGE; return negative ? LONG_MIN : LONG_MAX; }
    if (!negative) return (long)value;
    return value == (unsigned long)LONG_MAX + 1UL ? LONG_MIN : -(long)value;
}
