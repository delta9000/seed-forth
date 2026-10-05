/* Original seed-forth implementation; see LICENSE. Measured integer and
   character scanf over a string (sscanf) or an unbuffered stream (fscanf). */
#include <stdio.h>
#include <ctype.h>
#include <limits.h>
#include <errno.h>

/* Input with one byte of lookahead. A string ends at its NUL; a stream at
   EOF or a read error. At most one byte is ever held, so fscanf can return
   it with the stream's single ungetc slot. */
struct seed_scan_input {
    const char *text;
    FILE *stream;
    int held;
    int byte;
};

static int seed_scan_peek(struct seed_scan_input *input)
{
    if (input->stream == NULL)
        return *input->text ? (unsigned char)*input->text : EOF;
    if (!input->held) {
        input->byte = fgetc(input->stream);
        input->held = 1;
    }
    return input->byte;
}

static void seed_scan_next(struct seed_scan_input *input)
{
    if (input->stream == NULL) input->text++;
    else input->held = 0;
}

static int seed_scan_digit(int byte)
{
    if (byte >= '0' && byte <= '9') return byte - '0';
    if (byte >= 'a' && byte <= 'f') return byte - 'a' + 10;
    if (byte >= 'A' && byte <= 'F') return byte - 'A' + 10;
    return -1;
}

static int seed_scan(struct seed_scan_input *input, const char *format, va_list arguments)
{
    unsigned long value;
    unsigned long limit;
    int assigned = 0;
    int base;
    int conversion;
    int negative;
    int digit;
    int any;
    int overflow;
    while (*format) {
        if (isspace((unsigned char)*format)) {
            while (isspace((unsigned char)*format)) format++;
            while (seed_scan_peek(input) != EOF && isspace(seed_scan_peek(input)))
                seed_scan_next(input);
            continue;
        }
        conversion = (unsigned char)*format++;
        if (conversion != '%') {
            if (seed_scan_peek(input) == EOF) return assigned ? assigned : EOF;
            if (seed_scan_peek(input) != conversion) break;
            seed_scan_next(input);
            continue;
        }
        conversion = (unsigned char)*format;
        if (conversion != '%' && conversion != 'd' && conversion != 'o' &&
            conversion != 'x' && conversion != 'c') {
            errno = EINVAL;
            return assigned ? assigned : EOF;
        }
        format++;
        if (conversion == 'c') {
            /* One byte, whitespace included, as ISO C %c without a width. */
            if (seed_scan_peek(input) == EOF) return assigned ? assigned : EOF;
            *va_arg(arguments, char *) = (char)seed_scan_peek(input);
            seed_scan_next(input);
            assigned++;
            continue;
        }
        /* Every other supported conversion, including %%, skips input
           whitespace. Ordinary format characters above match without it. */
        while (seed_scan_peek(input) != EOF && isspace(seed_scan_peek(input)))
            seed_scan_next(input);
        if (seed_scan_peek(input) == EOF) return assigned ? assigned : EOF;
        if (conversion == '%') {
            if (seed_scan_peek(input) != '%') break;
            seed_scan_next(input);
            continue;
        }
        base = conversion == 'd' ? 10 : conversion == 'o' ? 8 : 16;
        negative = 0;
        if (seed_scan_peek(input) == '+' || seed_scan_peek(input) == '-') {
            negative = seed_scan_peek(input) == '-';
            seed_scan_next(input);
        }
        limit = conversion == 'd' ? (negative ? 2147483648UL : 2147483647UL) : UINT_MAX;
        value = 0; any = 0; overflow = 0;
        if (base == 16 && seed_scan_peek(input) == '0') {
            /* A leading zero is a digit unless a 0x prefix follows; an
               incomplete prefix is then a matching failure. */
            seed_scan_next(input);
            if (seed_scan_peek(input) == 'x' || seed_scan_peek(input) == 'X')
                seed_scan_next(input);
            else
                any = 1;
        }
        for (;;) {
            digit = seed_scan_digit(seed_scan_peek(input));
            if (digit < 0 || digit >= base) break;
            any = 1;
            if (value > limit / (unsigned long)base ||
                (value == limit / (unsigned long)base && (unsigned long)digit > limit % (unsigned long)base)) overflow = 1;
            if (!overflow) value = value * (unsigned long)base + (unsigned long)digit;
            seed_scan_next(input);
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
    return assigned;
}

int sscanf(const char *text, const char *format, ...)
{
    struct seed_scan_input input;
    va_list arguments;
    int result;
    if (text == NULL || format == NULL) { errno = EINVAL; return EOF; }
    input.text = text;
    input.stream = NULL;
    input.held = 0;
    input.byte = EOF;
    va_start(arguments, format);
    result = seed_scan(&input, format, arguments);
    va_end(arguments);
    return result;
}

int fscanf(FILE *stream, const char *format, ...)
{
    struct seed_scan_input input;
    va_list arguments;
    int result;
    if (stream == NULL || format == NULL) { errno = EINVAL; return EOF; }
    input.text = NULL;
    input.stream = stream;
    input.held = 0;
    input.byte = EOF;
    va_start(arguments, format);
    result = seed_scan(&input, format, arguments);
    va_end(arguments);
    /* The byte that ended the scan was read but not consumed. */
    if (input.held && input.byte != EOF) ungetc(input.byte, stream);
    return result;
}
