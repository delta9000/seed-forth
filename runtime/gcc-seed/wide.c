/* Original seed-forth implementation; see LICENSE. Fixed ASCII C/POSIX. */
#include <stdlib.h>
#include <wchar.h>
#include <wctype.h>
#include <errno.h>
#include <limits.h>
int iswprint(wint_t value) { return value >= 32 && value <= 126; }
int iswspace(wint_t value) { return value == 32 || (value >= 9 && value <= 13); }
/* C locale case mapping: only ASCII A-Z change; WEOF maps to itself. */
wint_t towlower(wint_t value) { return value >= 'A' && value <= 'Z' ? value + 32 : value; }
/* ASCII multibyte strings: every byte below 128 is one wide character.
   With a NULL destination the count is returned and COUNT is ignored. */
size_t mbstowcs(wchar_t *wide, const char *bytes, size_t count)
{
    size_t done = 0;
    unsigned char value;
    while (wide == NULL || done < count) {
        value = (unsigned char)bytes[done];
        if (value > 127) { errno = EILSEQ; return (size_t)-1; }
        if (wide) wide[done] = value;
        if (value == 0) break;
        done++;
    }
    return done;
}
int mbtowc(wchar_t *wide, const char *bytes, size_t count)
{
    unsigned char value;
    if (bytes == NULL) return 0;
    if (count == 0) { errno = EILSEQ; return -1; }
    value = (unsigned char)*bytes;
    if (value > 127) { errno = EILSEQ; return -1; }
    if (wide) *wide = value;
    return value == 0 ? 0 : 1;
}
int wctomb(char *bytes, wchar_t wide)
{
    if (bytes == NULL) return 0;
    if ((unsigned int)wide > 127) { errno = EILSEQ; return -1; }
    *bytes = (char)wide;
    return 1;
}
static int seed_wide_digit(wchar_t value)
{
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'A' && value <= 'Z') return value - 'A' + 10;
    if (value >= 'a' && value <= 'z') return value - 'a' + 10;
    return -1;
}
long wcstol(const wchar_t *text, wchar_t **end, int base)
{
    const wchar_t *cursor = text;
    unsigned long value = 0;
    unsigned long limit;
    unsigned long cutoff;
    unsigned long remainder;
    int negative = 0;
    int any = 0;
    int overflow = 0;
    int digit;
    if (end) *end = (wchar_t *)text;
    if (base != 0 && (base < 2 || base > 36)) { errno = EINVAL; return 0; }
    while (iswspace((wint_t)*cursor)) cursor++;
    if (*cursor == '+' || *cursor == '-') { negative = *cursor == '-'; cursor++; }
    if ((base == 0 || base == 16) && cursor[0] == '0'
        && (cursor[1] == 'x' || cursor[1] == 'X')
        && seed_wide_digit(cursor[2]) >= 0 && seed_wide_digit(cursor[2]) < 16) {
        cursor += 2;
        base = 16;
    }
    if (base == 0) base = *cursor == '0' ? 8 : 10;
    limit = (unsigned long)LONG_MAX + (unsigned long)negative;
    cutoff = limit / (unsigned long)base;
    remainder = limit % (unsigned long)base;
    for (;;) {
        digit = seed_wide_digit(*cursor);
        if (digit < 0 || digit >= base) break;
        any = 1;
        if (value > cutoff || (value == cutoff && (unsigned long)digit > remainder)) overflow = 1;
        if (!overflow) value = value * (unsigned long)base + (unsigned long)digit;
        cursor++;
    }
    if (!any) return 0;
    if (end) *end = (wchar_t *)cursor;
    if (overflow) { errno = ERANGE; return negative ? LONG_MIN : LONG_MAX; }
    if (negative && value == (unsigned long)LONG_MAX + 1UL) return LONG_MIN;
    return negative ? -(long)value : (long)value;
}
