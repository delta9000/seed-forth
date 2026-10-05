/* Original seed-forth implementation; see LICENSE. Fixed ASCII C locale. */
#include <stdlib.h>
#include <ctype.h>
#include <limits.h>
#include <errno.h>

static int seed_digit(unsigned char byte)
{
    if (byte >= '0' && byte <= '9') return byte - '0';
    if (byte >= 'A' && byte <= 'Z') return byte - 'A' + 10;
    if (byte >= 'a' && byte <= 'z') return byte - 'a' + 10;
    return -1;
}

/* Scan once for either conversion.  The sign selects the magnitude limit.
   Only invalid bases set errno here; range handling belongs to the caller. */
static unsigned long seed_scan(const char *text, char **end, int base,
                               unsigned long positive_limit,
                               unsigned long negative_limit,
                               int *negative, int *overflow)
{
    const char *cursor = text;
    unsigned long value = 0;
    unsigned long limit;
    unsigned long cutoff;
    unsigned long remainder;
    int any = 0;
    int digit;
    *negative = 0;
    *overflow = 0;
    if (end) *end = (char *)text;
    if (base != 0 && (base < 2 || base > 36)) {
        errno = EINVAL;
        return 0;
    }
    while (isspace((unsigned char)*cursor)) cursor++;
    if (*cursor == '+' || *cursor == '-') {
        *negative = *cursor == '-';
        cursor++;
    }
    if ((base == 0 || base == 16) && cursor[0] == '0'
        && (cursor[1] == 'x' || cursor[1] == 'X')
        && seed_digit((unsigned char)cursor[2]) >= 0
        && seed_digit((unsigned char)cursor[2]) < 16) {
        cursor += 2;
        base = 16;
    }
    if (base == 0) base = *cursor == '0' ? 8 : 10;
    limit = *negative ? negative_limit : positive_limit;
    cutoff = limit / (unsigned long)base;
    remainder = limit % (unsigned long)base;
    for (;;) {
        digit = seed_digit((unsigned char)*cursor);
        if (digit < 0 || digit >= base) break;
        any = 1;
        if (value > cutoff || (value == cutoff && (unsigned long)digit > remainder))
            *overflow = 1;
        if (!*overflow) value = value * (unsigned long)base + (unsigned long)digit;
        cursor++;
    }
    if (any && end) *end = (char *)cursor;
    return value;
}

unsigned long strtoul(const char *text, char **end, int base)
{
    unsigned long value;
    int negative;
    int overflow;
    value = seed_scan(text, end, base, ULONG_MAX, ULONG_MAX,
                      &negative, &overflow);
    if (overflow) {
        errno = ERANGE;
        return ULONG_MAX;
    }
    return negative ? 0UL - value : value;
}

/* LONG_MAX + 1 is an unsigned magnitude, so LONG_MIN converts exactly. */
long strtol(const char *text, char **end, int base)
{
    unsigned long value;
    int negative;
    int overflow;
    value = seed_scan(text, end, base, (unsigned long)LONG_MAX,
                      (unsigned long)LONG_MAX + 1, &negative, &overflow);
    if (overflow) {
        errno = ERANGE;
        return negative ? LONG_MIN : LONG_MAX;
    }
    if (negative) return value == (unsigned long)LONG_MAX + 1 ? LONG_MIN : -(long)value;
    return (long)value;
}
