/* Original seed-forth implementation; see LICENSE. Measured integer scanf. */
#include <stdio.h>
#include <ctype.h>
#include <limits.h>
#include <errno.h>

static int seed_scan_digit(unsigned char byte)
{
    if (byte >= '0' && byte <= '9') return byte - '0';
    if (byte >= 'a' && byte <= 'f') return byte - 'a' + 10;
    if (byte >= 'A' && byte <= 'F') return byte - 'A' + 10;
    return -1;
}

int sscanf(const char *text, const char *format, ...)
{
    va_list arguments;
    unsigned long value;
    unsigned long limit;
    int assigned = 0;
    int result = 0;
    int base;
    int conversion;
    int negative;
    int digit;
    int any;
    int overflow;
    if (text == NULL || format == NULL) { errno = EINVAL; return EOF; }
    va_start(arguments, format);
    while (*format) {
        if (isspace((unsigned char)*format)) {
            while (isspace((unsigned char)*format)) format++;
            while (isspace((unsigned char)*text)) text++;
            continue;
        }
        conversion = (unsigned char)*format++;
        if (conversion != '%') {
            if (!*text) { result = assigned ? assigned : EOF; goto done; }
            if ((unsigned char)*text != conversion) break;
            text++;
            continue;
        }
        conversion = (unsigned char)*format;
        if (conversion != '%' && conversion != 'd' && conversion != 'o' && conversion != 'x') {
            errno = EINVAL; result = assigned ? assigned : EOF; goto done;
        }
        format++;
        /* Every supported conversion, including %%, skips input whitespace.
           Ordinary format characters above match without that step. */
        while (isspace((unsigned char)*text)) text++;
        if (!*text) { result = assigned ? assigned : EOF; goto done; }
        if (conversion == '%') {
            if (*text != '%') break;
            text++;
            continue;
        }
        base = conversion == 'd' ? 10 : conversion == 'o' ? 8 : 16;
        negative = 0;
        if (*text == '+' || *text == '-') { negative = *text == '-'; text++; }
        if (base == 16 && text[0] == '0' && (text[1] == 'x' || text[1] == 'X')) text += 2;
        limit = conversion == 'd' ? (negative ? 2147483648UL : 2147483647UL) : UINT_MAX;
        value = 0; any = 0; overflow = 0;
        for (;;) {
            digit = seed_scan_digit((unsigned char)*text);
            if (digit < 0 || digit >= base) break;
            any = 1;
            if (value > limit / (unsigned long)base ||
                (value == limit / (unsigned long)base && (unsigned long)digit > limit % (unsigned long)base)) overflow = 1;
            if (!overflow) value = value * (unsigned long)base + (unsigned long)digit;
            text++;
        }
        if (!any) break;
        if (overflow) { errno = ERANGE; break; }
        if (conversion == 'd') {
            *va_arg(arguments,int *) = negative ? (value == 2147483648UL ? INT_MIN : -(int)value) : (int)value;
        } else {
            *va_arg(arguments,unsigned int *) = negative ? 0U - (unsigned int)value : (unsigned int)value;
        }
        assigned++;
    }
    result = assigned;
done:
    va_end(arguments);
    return result;
}
