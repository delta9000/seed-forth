/* Original seed-forth implementation; see LICENSE. Fixed ASCII C locale. */
#include <stdlib.h>
#include <ctype.h>
#include <limits.h>
#include <errno.h>
int atoi(const char *text)
{
    unsigned int value = 0;
    unsigned int limit;
    unsigned int digit;
    int negative = 0;
    int overflow = 0;
    while (isspace((unsigned char)*text)) text++;
    if (*text == '+' || *text == '-') { negative = *text == '-'; text++; }
    limit = negative ? 2147483648U : 2147483647U;
    while (*text >= '0' && *text <= '9') {
        digit = (unsigned int)(*text++ - '0');
        if (value > limit / 10U || (value == limit / 10U && digit > limit % 10U)) overflow = 1;
        if (!overflow) value = value * 10U + digit;
    }
    if (overflow) { errno = ERANGE; return negative ? INT_MIN : INT_MAX; }
    return negative ? (value == 2147483648U ? INT_MIN : -(int)value) : (int)value;
}
