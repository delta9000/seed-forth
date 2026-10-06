/* Differential fixture for exact floating printf conversions.
   Built twice from this one source: by the Forth compiler against
   runtime/gcc-seed (production) and by host GCC against glibc (oracle
   only). Both print one line per case; printf-float-check.py requires the
   two outputs to be byte-identical. Usage: prog SECTION SEED COUNT. */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>

static unsigned long state;
static char out[70000];

static unsigned long next(void)
{
    /* xorshift64* */
    state ^= state >> 12;
    state ^= state << 25;
    state ^= state >> 27;
    return state * 2685821657736338717UL;
}

static unsigned long below(unsigned long limit) { return next() % limit; }

static double from_bits(unsigned long bits)
{
    double value;
    memcpy(&value, &bits, 8);
    return value;
}

static long double from_ext(unsigned long mantissa, unsigned int top)
{
    unsigned char bytes[16];
    long double value;
    memset(bytes, 0, 16);
    memcpy(bytes, &mantissa, 8);
    bytes[8] = (unsigned char)(top & 255);
    bytes[9] = (unsigned char)(top >> 8);
    memcpy(&value, bytes, 16);
    return value;
}

static void show(const char *format, int count)
{
    printf("%s|%d|%s\n", format, count, out);
}

static void one(const char *format, double value)
{
    int count = snprintf(out, sizeof out, format, value);
    show(format, count);
}

static void one_star(const char *format, int width, int precision, double value)
{
    int count = snprintf(out, sizeof out, format, width, precision, value);
    printf("%d,%d:", width, precision);
    show(format, count);
}

static void one_long(const char *format, long double value)
{
    int count = snprintf(out, sizeof out, format, value);
    show(format, count);
}

static const char conversions[] = "eEfFgGaA";

/* A random format: flags, optional width, optional precision, conversion. */
static void random_format(char *format, int max_precision, int is_long)
{
    int length = 0;
    int flags = (int)below(32);
    format[length++] = '%';
    if (flags & 1) format[length++] = '-';
    if (flags & 2) format[length++] = '+';
    if (flags & 4) format[length++] = ' ';
    if (flags & 8) format[length++] = '#';
    if (flags & 16) format[length++] = '0';
    if (below(3)) length += sprintf(format + length, "%d", (int)below(40));
    if (below(4)) length += sprintf(format + length, ".%d", (int)below((unsigned long)max_precision + 1));
    else if (below(5) == 0) format[length++] = '.';
    if (is_long) format[length++] = 'L';
    else if (below(8) == 0) format[length++] = 'l';
    format[length++] = conversions[below(8)];
    format[length] = 0;
}

/* Random binary64 bit patterns across every exponent. */
static void section_random(long count)
{
    char format[64];
    long index;
    for (index = 0; index < count; index++) {
        unsigned long bits = next();
        if (below(4) == 0) bits = (bits & 0x800fffffffffffffUL) | (below(2048) << 52);
        if (below(8) == 0) bits &= 0x800fffffffffffffUL; /* subnormal */
        if (below(8) == 0) bits &= ~((1UL << below(53)) - 1); /* short mantissa */
        random_format(format, 60, 0);
        one(format, from_bits(bits));
    }
}

/* Every precision 0..60 for %e %f %g (and %a 0..16) on varied values. */
static void section_precision(long count)
{
    char format[32];
    long index;
    int precision;
    int kind;
    for (index = 0; index < count; index++) {
        unsigned long bits = next();
        double value;
        if (index % 3 == 0) bits = (bits & 0x800fffffffffffffUL) | ((1023UL - 40 + below(80)) << 52);
        value = from_bits(bits);
        if ((bits >> 52 & 2047) == 2047) value = 1.0 / 3.0;
        for (kind = 0; kind < 3; kind++) {
            for (precision = 0; precision <= 60; precision++) {
                sprintf(format, "%%.%d%c", precision, "efg"[kind]);
                one(format, value);
            }
        }
        for (precision = 0; precision <= 16; precision++) {
            sprintf(format, "%%.%da", precision);
            one(format, value);
        }
    }
}

/* Exact ties: m * 2^-k has exactly k fraction digits ending in 5. */
static void section_ties(long count)
{
    char format[32];
    long index;
    int precision;
    for (index = 0; index < count; index++) {
        int bits = 1 + (int)below(53);
        unsigned long mantissa = (next() >> (64 - bits)) | 1UL;
        int shift = (int)below(70);
        double value = (double)mantissa;
        int step;
        for (step = 0; step < shift; step++) value = value * 0.5;
        if (below(2)) value = -value;
        for (precision = shift > 3 ? shift - 3 : 0; precision <= shift + 1; precision++) {
            sprintf(format, "%%.%df", precision);
            one(format, value);
        }
        for (precision = 0; precision < 20; precision++) {
            sprintf(format, "%%.%de", precision);
            one(format, value);
            sprintf(format, "%%.%dg", precision);
            one(format, value);
        }
        /* Decimal-looking ties with integer values: 25, 125, 2500... */
        value = (double)(below(100000) * 10 + 5);
        for (precision = 0; precision < 7; precision++) {
            sprintf(format, "%%.%de", precision);
            one(format, value);
            sprintf(format, "%%.%dg", precision);
            one(format, value);
        }
        sprintf(format, "%%.%da", (int)below(14));
        one(format, from_bits(next()));
    }
}

/* All 32 flag sets, widths and specials, plus star arguments. */
static void section_flags(void)
{
    char format[64];
    double values[24];
    int value_count = 0;
    int flag;
    int conversion;
    int width;
    int index;
    values[value_count++] = 0.0;
    values[value_count++] = -0.0;
    values[value_count++] = 1.0;
    values[value_count++] = -1.5;
    values[value_count++] = 0.1;
    values[value_count++] = 123456.789;
    values[value_count++] = 1e-5;
    values[value_count++] = 9.9999995e-5;
    values[value_count++] = 999999.5;
    values[value_count++] = 1e100;
    values[value_count++] = -1e-300;
    values[value_count++] = from_bits(1);
    values[value_count++] = from_bits(0x000fffffffffffffUL);
    values[value_count++] = from_bits(0x0010000000000000UL);
    values[value_count++] = from_bits(0x7fefffffffffffffUL);
    values[value_count++] = from_bits(0x7ff0000000000000UL);
    values[value_count++] = from_bits(0xfff0000000000000UL);
    values[value_count++] = from_bits(0x7ff8000000000000UL);
    values[value_count++] = from_bits(0xfff8000000000000UL);
    values[value_count++] = from_bits(0x7ff0000000000001UL);
    values[value_count++] = 0.5;
    values[value_count++] = 2.5;
    values[value_count++] = 1e21;
    values[value_count++] = 4.35;
    for (flag = 0; flag < 32; flag++) {
        for (conversion = 0; conversion < 8; conversion++) {
            for (width = 0; width < 4; width++) {
                int precision;
                for (precision = -2; precision < 4; precision++) {
                    int length = 0;
                    format[length++] = '%';
                    if (flag & 1) format[length++] = '-';
                    if (flag & 2) format[length++] = '+';
                    if (flag & 4) format[length++] = ' ';
                    if (flag & 8) format[length++] = '#';
                    if (flag & 16) format[length++] = '0';
                    if (width) length += sprintf(format + length, "%d", width * 7 - 4);
                    if (precision == -1) format[length++] = '.';
                    if (precision >= 0) length += sprintf(format + length, ".%d", precision * 3);
                    format[length++] = conversions[conversion];
                    format[length] = 0;
                    for (index = 0; index < value_count; index++) one(format, values[index]);
                }
            }
        }
    }
    for (index = 0; index < value_count; index++) {
        for (width = -25; width <= 25; width += 5) {
            int precision;
            for (precision = -3; precision < 25; precision += 4) {
                one_star("%*.*e", width, precision, values[index]);
                one_star("%0*.*f", width, precision, values[index]);
                one_star("%+*.*g", width, precision, values[index]);
                one_star("%#*.*G", width, precision, values[index]);
                one_star("%-*.*a", width, precision, values[index]);
                one_star("%0*.*A", width, precision, values[index]);
            }
        }
    }
}

/* Long double: valid x87 normals, subnormals and specials. */
static void section_long(long count)
{
    char format[64];
    long index;
    for (index = 0; index < count; index++) {
        unsigned long mantissa = next();
        unsigned int top;
        unsigned int exponent;
        if (below(4) == 0) exponent = (unsigned int)below(32767);
        else exponent = 16383 - 400 + (unsigned int)below(800);
        if (below(10) == 0) exponent = 0;
        if (exponent == 0) mantissa &= 0x7fffffffffffffffUL;
        else mantissa |= 0x8000000000000000UL;
        if (below(5) == 0) mantissa &= ~((1UL << below(64)) - 1) | 0x8000000000000000UL;
        if (exponent == 0 && below(2)) mantissa >>= below(64);
        top = exponent | (below(2) ? 32768U : 0U);
        random_format(format, 40, 1);
        one_long(format, from_ext(mantissa, top));
    }
    one_long("%Lf", from_ext(0x8000000000000000UL, 32767));
    one_long("%Le", from_ext(0x8000000000000000UL, 32767 | 32768));
    one_long("%Lg", from_ext(0xc000000000000000UL, 32767));
    one_long("%LA", from_ext(0xc000000000000000UL, 32767 | 32768));
    one_long("%La", from_ext(0, 0));
    one_long("%La", from_ext(1, 0));
    one_long("%.0La", from_ext(0xf800000000000000UL, 16383));
    one_long("%.1La", from_ext(0xff80000000000000UL, 16383));
    one_long("%.3Le", from_ext(1, 0));
    one_long("%.3Lf", from_ext(0xffffffffffffffffUL, 32766));
}

/* Huge precisions and widths, truncation and every printf entry point. */
static int via_vsnprintf(char *buffer, size_t size, const char *format, ...)
{
    va_list arguments;
    int result;
    va_start(arguments, format);
    result = vsnprintf(buffer, size, format, arguments);
    va_end(arguments);
    return result;
}

static int via_vsprintf(char *buffer, const char *format, ...)
{
    va_list arguments;
    int result;
    va_start(arguments, format);
    result = vsprintf(buffer, format, arguments);
    va_end(arguments);
    return result;
}

static void section_large(void)
{
    char small[16];
    int count;
    size_t size;
    one("%.1000f", 1e-300);
    one("%.1100f", from_bits(1));
    one("%.800e", from_bits(1));
    one("%.770g", from_bits(1));
    one("%.0f", from_bits(0x7fefffffffffffffUL));
    one("%.400f", from_bits(0x7fefffffffffffffUL));
    one("%5000.3f", 3.14159);
    one("%-3000.2e|", 2.71828);
    one("%#.0a", 0.0);
    one("%.20a", 1.0);
    one("%.60g", 0.1);
    one("%.17g", 0.1);
    one("%.17g", 1.0 / 3.0);
    for (size = 0; size < 12; size++) {
        memset(small, 'x', sizeof small);
        count = snprintf(small, size, "%.5f|%g", 3.14159265, 2.5e-10);
        small[15] = 0;
        printf("snprintf %d %d %s\n", (int)size, count, size ? small : "-");
        memset(small, 'x', sizeof small);
        count = via_vsnprintf(small, size, "%e", -1234.5);
        small[15] = 0;
        printf("vsnprintf %d %d %s\n", (int)size, count, size ? small : "-");
    }
    count = sprintf(out, "%g %e %f %a", 1e-10, 2e10, -3.25, 0.75);
    show("sprintf", count);
    count = via_vsprintf(out, "%G %E %F %A", 1e-10, 2e10, -3.25, 0.75);
    show("vsprintf", count);
    count = printf("printf %g %10.3f %-8e|\n", 0.1, 2.0 / 3.0, 1e300);
    printf("printf-count %d\n", count);
    count = fprintf(stdout, "fprintf %.3g %+.0f\n", 1234567.0, 0.5);
    printf("fprintf-count %d\n", count);
    count = snprintf(out, sizeof out, "%d %g %s %.2f %c %Lg %x", 42, 0.25, "str", 1.005,
                     'z', from_ext(0xa000000000000000UL, 16384), 255);
    show("mixed", count);
}

int main(int argc, char **argv)
{
    long count;
    if (argc != 4) return 2;
    state = strtoul(argv[2], NULL, 10) * 2 + 0x9e3779b97f4a7c15UL;
    count = (long)strtoul(argv[3], NULL, 10);
    if (!strcmp(argv[1], "random")) section_random(count);
    else if (!strcmp(argv[1], "precision")) section_precision(count);
    else if (!strcmp(argv[1], "ties")) section_ties(count);
    else if (!strcmp(argv[1], "flags")) section_flags();
    else if (!strcmp(argv[1], "long")) section_long(count);
    else if (!strcmp(argv[1], "large")) section_large();
    else return 2;
    return fflush(stdout) != 0;
}
