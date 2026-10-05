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

unsigned long strtoul(const char *text, char **end, int base)
{
    const char *cursor = text;
    unsigned long value = 0;
    unsigned long cutoff;
    unsigned long remainder;
    int negative = 0;
    int any = 0;
    int overflow = 0;
    int digit;
    if (end) *end = (char *)text;
    if (base != 0 && (base < 2 || base > 36)) {
        errno = EINVAL;
        return 0;
    }
    while (isspace((unsigned char)*cursor)) cursor++;
    if (*cursor == '+' || *cursor == '-') {
        negative = *cursor == '-';
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
    cutoff = ULONG_MAX / (unsigned long)base;
    remainder = ULONG_MAX % (unsigned long)base;
    for (;;) {
        digit = seed_digit((unsigned char)*cursor);
        if (digit < 0 || digit >= base) break;
        any = 1;
        if (value > cutoff || (value == cutoff && (unsigned long)digit > remainder))
            overflow = 1;
        if (!overflow) value = value * (unsigned long)base + (unsigned long)digit;
        cursor++;
    }
    if (!any) return 0;
    if (end) *end = (char *)cursor;
    if (overflow) {
        errno = ERANGE;
        return ULONG_MAX;
    }
    return negative ? 0UL - value : value;
}

/* Signed conversion with strtoul's parsing rules.  The magnitude limit is
   LONG_MAX, or LONG_MAX + 1 for a negative result, so LONG_MIN converts
   exactly; overflow consumes every valid digit and returns LONG_MAX or
   LONG_MIN with ERANGE. */
long strtol(const char *text, char **end, int base)
{
    const char *cursor = text;
    unsigned long limit;
    unsigned long value = 0;
    int negative = 0;
    int any = 0;
    int overflow = 0;
    int digit;
    if (end) *end = (char *)text;
    if (base != 0 && (base < 2 || base > 36)) {
        errno = EINVAL;
        return 0;
    }
    while (isspace((unsigned char)*cursor)) cursor++;
    if (*cursor == '+' || *cursor == '-') {
        negative = *cursor == '-';
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
    limit = negative ? (unsigned long)LONG_MAX + 1 : (unsigned long)LONG_MAX;
    for (;;) {
        digit = seed_digit((unsigned char)*cursor);
        if (digit < 0 || digit >= base) break;
        any = 1;
        if (value > (limit - (unsigned long)digit) / (unsigned long)base)
            overflow = 1;
        if (!overflow) value = value * (unsigned long)base + (unsigned long)digit;
        cursor++;
    }
    if (!any) return 0;
    if (end) *end = (char *)cursor;
    if (overflow) {
        errno = ERANGE;
        return negative ? LONG_MIN : LONG_MAX;
    }
    if (negative) return value == (unsigned long)LONG_MAX + 1 ? LONG_MIN : -(long)value;
    return (long)value;
}
