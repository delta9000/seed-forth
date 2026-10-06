/* Original seed-forth implementation; see LICENSE and CALENDAR.md.
   C-locale strftime with the GNU flags, widths and conversions, matching
   glibc's output for any field values. Fields are used as given, without
   normalization; %z, %Z use the current TZ (see calendar.c). */
#include <time.h>
#include <string.h>
#include <limits.h>

const char *__seed_calendar_zone(int isdst, long *gmtoff);

/* Output cursor. LENGTH counts every byte produced, written or not; bytes
   are stored only while one byte remains for the terminator. A null BUFFER
   only measures. UPPER forces capitals (an enclosing ^ composite). */
struct seed_strftime_out {
    char *buffer;
    size_t size;
    size_t length;
    int upper;
};

/* One conversion's flags: PAD is 0, '_', '-' or '0'; WIDTH is -1 when
   absent. */
struct seed_strftime_spec {
    int pad;
    int upper;
    int swap;
    int lower;
    long width;
    int modifier;
};

static const char *const seed_strftime_days[7] = {
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
};
static const char *const seed_strftime_months[12] = {
    "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December"
};

static void seed_strftime_fill(struct seed_strftime_out *out, int c, long count)
{
    while (count > 0) {
        if (out->buffer && out->length + 1 < out->size) {
            out->buffer[out->length++] = (char)c;
            count--;
        } else {
            out->length += (size_t)count;
            count = 0;
        }
    }
}

static void seed_strftime_byte(struct seed_strftime_out *out, int c)
{
    if (out->upper && c >= 'a' && c <= 'z') c -= 'a' - 'A';
    seed_strftime_fill(out, c, 1);
}

/* Text TEXT[0..LENGTH) right aligned in the field width (zeros with the 0
   flag, spaces otherwise), case changed as the flags ask. */
static void seed_strftime_text(struct seed_strftime_out *out,
                               const struct seed_strftime_spec *spec,
                               const char *text, long length)
{
    long i;
    if (spec->width > length)
        seed_strftime_fill(out, spec->pad == '0' ? '0' : ' ', spec->width - length);
    for (i = 0; i < length; i++) {
        int c = (unsigned char)text[i];
        if (spec->lower) {
            if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
        } else if (spec->upper) {
            if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
        }
        seed_strftime_byte(out, c);
    }
}

/* DIGITS (no sign) of a value that is NEGATIVE or not, padded to at least
   MINIMUM characters: '_' pads with spaces before the sign, the default
   and '0' with zeros after it, '-' not at all. Whatever is left of the
   field width then applies as for text. */
static void seed_strftime_padded(struct seed_strftime_out *out,
                                 struct seed_strftime_spec *spec,
                                 const char *digits, long length,
                                 int negative, long minimum)
{
    char text[32];
    long total = length + negative;
    long padding;
    if (negative) text[0] = '-';
    memcpy(text + negative, digits, (size_t)length);
    if (spec->pad != '-') {
        padding = minimum - total;
        if (padding > 0) {
            if (spec->pad == '_') {
                seed_strftime_fill(out, ' ', padding);
                spec->width = spec->width > padding ? spec->width - padding : 0;
            } else {
                if (negative) seed_strftime_byte(out, '-');
                seed_strftime_fill(out, '0', padding);
                spec->width = 0;
                seed_strftime_text(out, spec, text + negative, length);
                return;
            }
        }
    }
    seed_strftime_text(out, spec, text, total);
}

/* An int-valued field: VALUE wraps to 32 bits as int arithmetic would, and
   is printed with at least MINIMUM digits (or the field width). */
static void seed_strftime_number(struct seed_strftime_out *out,
                                 struct seed_strftime_spec *spec,
                                 long value, long minimum)
{
    char digits[24];
    char reversed[24];
    long length = 0;
    long i;
    unsigned long magnitude;
    int negative;
    value &= 0xffffffffL;
    if (value >= 0x80000000L) value -= 0x100000000L;
    negative = value < 0;
    magnitude = (unsigned long)(negative ? -value : value);
    do {
        reversed[length++] = (char)('0' + magnitude % 10);
        magnitude /= 10;
    } while (magnitude);
    for (i = 0; i < length; i++) digits[i] = reversed[length - 1 - i];
    if (spec->width > minimum) minimum = spec->width;
    seed_strftime_padded(out, spec, digits, length, negative, minimum);
}

/* Space padded by default (%e %k %l): '0' and '-' still override. */
static void seed_strftime_spaced(struct seed_strftime_out *out,
                                 struct seed_strftime_spec *spec,
                                 long value, long minimum)
{
    if (spec->pad != '0' && spec->pad != '-') spec->pad = '_';
    seed_strftime_number(out, spec, value, minimum);
}

/* VALUE as 32-bit int arithmetic would leave it (wrapping). */
static long seed_strftime_int(long value)
{
    value &= 0xffffffffL;
    if (value >= 0x80000000L) value -= 0x100000000L;
    return value;
}

/* Days since the Monday that starts ISO week 1 of the year (negative
   before it), for day of year YDAY falling on weekday WDAY. */
static long seed_strftime_iso_days(long yday, long wday)
{
    long big = (366 / 7 + 2) * 7;
    long shift = seed_strftime_int(seed_strftime_int(seed_strftime_int(yday - wday) + 4)
                                   + big) % 7;
    return seed_strftime_int(seed_strftime_int(yday - shift) + 4) - 1;
}

static int seed_strftime_leap(long year)
{
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

static void seed_strftime_run(struct seed_strftime_out *out, const char *format,
                              const struct tm *tm);

/* A composite such as %c: measured first, so that the field width pads it
   as one piece; ^ capitalizes all of it. */
static void seed_strftime_sub(struct seed_strftime_out *out,
                              const struct seed_strftime_spec *spec,
                              const char *format, const struct tm *tm)
{
    struct seed_strftime_out measure;
    int upper = out->upper;
    measure.buffer = NULL;
    measure.size = 0;
    measure.length = 0;
    measure.upper = 0;
    seed_strftime_run(&measure, format, tm);
    if (spec->width > (long)measure.length)
        seed_strftime_fill(out, spec->pad == '0' ? '0' : ' ',
                           spec->width - (long)measure.length);
    if (spec->upper) out->upper = 1;
    seed_strftime_run(out, format, tm);
    out->upper = upper;
}

static void seed_strftime_run(struct seed_strftime_out *out, const char *format,
                              const struct tm *tm)
{
    const char *f;
    for (f = format; *f; f++) {
        struct seed_strftime_spec spec;
        const char *start;
        const char *text;
        long value;
        long year;
        long adjust;
        long days;
        int done;
        if (*f != '%') {
            seed_strftime_byte(out, (unsigned char)*f);
            continue;
        }
        start = f;
        spec.pad = 0;
        spec.upper = 0;
        spec.swap = 0;
        spec.lower = 0;
        spec.width = -1;
        for (;;) {
            f++;
            if (*f == '_' || *f == '-' || *f == '0') spec.pad = *f;
            else if (*f == '^') spec.upper = 1;
            else if (*f == '#') spec.swap = 1;
            else break;
        }
        if (*f >= '0' && *f <= '9') {
            spec.width = 0;
            do {
                if (spec.width > INT_MAX / 10
                    || (spec.width == INT_MAX / 10 && *f - '0' > INT_MAX % 10))
                    spec.width = INT_MAX;
                else
                    spec.width = spec.width * 10 + (*f - '0');
                f++;
            } while (*f >= '0' && *f <= '9');
        }
        spec.modifier = 0;
        if (*f == 'E' || *f == 'O') spec.modifier = *f++;
        done = 1;
        switch (*f) {
        case '%':
            if (spec.modifier) done = 0;
            else seed_strftime_text(out, &spec, "%", 1);
            break;
        case 'a':
        case 'A':
            if (spec.modifier) {
                done = 0;
                break;
            }
            if (spec.swap) spec.upper = 1;
            if (tm->tm_wday < 0 || tm->tm_wday > 6) text = "?";
            else text = seed_strftime_days[tm->tm_wday];
            seed_strftime_text(out, &spec, text, *f == 'a' && *text != '?' ? 3
                               : (long)strlen(text));
            break;
        case 'b':
        case 'h':
        case 'B':
            /* O selects the C locale's (identical) standalone names; for
               %b and %h, # takes effect even before an invalid E. */
            if (*f != 'B' && spec.swap) spec.upper = 1;
            if (spec.modifier == 'E') {
                done = 0;
                break;
            }
            if (spec.swap) spec.upper = 1;
            if (tm->tm_mon < 0 || tm->tm_mon > 11) text = "?";
            else text = seed_strftime_months[tm->tm_mon];
            seed_strftime_text(out, &spec, text, *f != 'B' && *text != '?' ? 3
                               : (long)strlen(text));
            break;
        case 'c':
            if (spec.modifier == 'O') done = 0;
            else seed_strftime_sub(out, &spec, "%a %b %e %H:%M:%S %Y", tm);
            break;
        case 'C':
            year = seed_strftime_int((long)tm->tm_year + 1900);
            seed_strftime_number(out, &spec, year / 100 - (year % 100 < 0), 1);
            break;
        case 'x':
            if (spec.modifier == 'O') done = 0;
            else seed_strftime_sub(out, &spec, "%m/%d/%y", tm);
            break;
        case 'X':
            if (spec.modifier == 'O') done = 0;
            else seed_strftime_sub(out, &spec, "%H:%M:%S", tm);
            break;
        case 'D':
            if (spec.modifier) done = 0;
            else seed_strftime_sub(out, &spec, "%m/%d/%y", tm);
            break;
        case 'F':
            if (spec.modifier) done = 0;
            else seed_strftime_sub(out, &spec, "%Y-%m-%d", tm);
            break;
        case 'R':
            seed_strftime_sub(out, &spec, "%H:%M", tm);
            break;
        case 'r':
            seed_strftime_sub(out, &spec, "%I:%M:%S %p", tm);
            break;
        case 'T':
            seed_strftime_sub(out, &spec, "%H:%M:%S", tm);
            break;
        case 'd':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_number(out, &spec, tm->tm_mday, 2);
            break;
        case 'e':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_spaced(out, &spec, tm->tm_mday, 2);
            break;
        case 'H':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_number(out, &spec, tm->tm_hour, 2);
            break;
        case 'I':
        case 'l':
            if (spec.modifier == 'E') {
                done = 0;
                break;
            }
            value = tm->tm_hour;
            if (value > 12) value -= 12;
            else if (value == 0) value = 12;
            if (*f == 'I') seed_strftime_number(out, &spec, value, 2);
            else seed_strftime_spaced(out, &spec, value, 2);
            break;
        case 'k':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_spaced(out, &spec, tm->tm_hour, 2);
            break;
        case 'j':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_number(out, &spec, tm->tm_yday + 1L, 3);
            break;
        case 'm':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_number(out, &spec, tm->tm_mon + 1L, 2);
            break;
        case 'M':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_number(out, &spec, tm->tm_min, 2);
            break;
        case 'S':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_number(out, &spec, tm->tm_sec, 2);
            break;
        case 'n':
            seed_strftime_text(out, &spec, "\n", 1);
            break;
        case 't':
            seed_strftime_text(out, &spec, "\t", 1);
            break;
        case 'P':
        case 'p':
            if (*f == 'P') spec.lower = 1;
            if (spec.swap) {
                spec.upper = 0;
                spec.lower = 1;
            }
            seed_strftime_text(out, &spec, tm->tm_hour > 11 ? "PM" : "AM", 2);
            break;
        case 's': {
            struct tm copy;
            char reversed[24];
            char digits[24];
            long length = 0;
            long i;
            long t;
            int negative;
            copy = *tm;
            t = mktime(&copy);
            negative = t < 0;
            do {
                long digit = t % 10;
                t /= 10;
                reversed[length++] = (char)('0' + (negative ? -digit : digit));
            } while (t != 0);
            for (i = 0; i < length; i++) digits[i] = reversed[length - 1 - i];
            seed_strftime_padded(out, &spec, digits, length, negative, 1);
            break;
        }
        case 'u':
            seed_strftime_number(out, &spec, seed_strftime_int(seed_strftime_int(
                                     tm->tm_wday - 1L) + 7) % 7 + 1, 1);
            break;
        case 'w':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_number(out, &spec, tm->tm_wday, 1);
            break;
        case 'U':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_number(out, &spec,
                                      seed_strftime_int(seed_strftime_int(
                                          (long)tm->tm_yday - tm->tm_wday) + 7) / 7, 2);
            break;
        case 'W':
            if (spec.modifier == 'E') done = 0;
            else seed_strftime_number(out, &spec,
                                      seed_strftime_int(seed_strftime_int(
                                          tm->tm_yday - seed_strftime_int(
                                              seed_strftime_int(tm->tm_wday - 1L) + 7) % 7)
                                                        + 7) / 7, 2);
            break;
        case 'V':
        case 'g':
        case 'G':
            if (spec.modifier == 'E') {
                done = 0;
                break;
            }
            /* Same leap status as tm_year + 1900, without overflow. */
            year = (long)tm->tm_year + (tm->tm_year < 0 ? 300 : -100);
            adjust = 0;
            days = seed_strftime_iso_days(tm->tm_yday, tm->tm_wday);
            if (days < 0) {
                adjust = -1;
                days = seed_strftime_iso_days(seed_strftime_int(tm->tm_yday + 365L
                                              + seed_strftime_leap(year - 1)),
                                              tm->tm_wday);
            } else {
                long next = seed_strftime_iso_days(seed_strftime_int(tm->tm_yday
                                                   - (365L + seed_strftime_leap(year))),
                                                   tm->tm_wday);
                if (next >= 0) {
                    adjust = 1;
                    days = next;
                }
            }
            if (*f == 'V') {
                seed_strftime_number(out, &spec, days / 7 + 1, 2);
            } else if (*f == 'G') {
                seed_strftime_number(out, &spec, (long)tm->tm_year + 1900 + adjust, 1);
            } else {
                value = (seed_strftime_int((long)tm->tm_year + 1900 + adjust) % 100
                         + 100) % 100;
                seed_strftime_number(out, &spec, value, 2);
            }
            break;
        case 'y':
            value = (tm->tm_year % 100 + 100) % 100;
            seed_strftime_number(out, &spec, value, 2);
            break;
        case 'Y':
            if (spec.modifier == 'O') done = 0;
            else seed_strftime_number(out, &spec, (long)tm->tm_year + 1900, 1);
            break;
        case 'z': {
            long offset;
            if (tm->tm_isdst < 0) break;
            __seed_calendar_zone(tm->tm_isdst, &offset);
            if (offset < 0) {
                seed_strftime_text(out, &spec, "-", 1);
                offset = -offset;
            } else {
                seed_strftime_text(out, &spec, "+", 1);
            }
            offset /= 60;
            seed_strftime_number(out, &spec, offset / 60 * 100 + offset % 60, 4);
            break;
        }
        case 'Z':
            if (spec.swap) {
                spec.upper = 0;
                spec.lower = 1;
            }
            if (tm->tm_isdst < 0) text = "";
            else if (tm->tm_isdst > 1) text = "?";
            else text = __seed_calendar_zone(tm->tm_isdst, NULL);
            seed_strftime_text(out, &spec, text, (long)strlen(text));
            break;
        case '\0':
            /* A trailing '%' sequence is copied; stop at the terminator. */
            f--;
            done = 0;
            break;
        default:
            done = 0;
            break;
        }
        if (!done) {
            /* Unknown or invalid: copy back to the nearest '%' verbatim. */
            const char *back = f;
            while (*back != '%') back--;
            seed_strftime_text(out, &spec, back, (long)(f - back) + 1);
        }
        (void)start;
    }
}

size_t strftime(char *buffer, size_t size, const char *format, const struct tm *tm)
{
    struct seed_strftime_out out;
    out.buffer = buffer;
    out.size = size;
    out.length = 0;
    out.upper = 0;
    seed_strftime_run(&out, format, tm);
    if (out.length >= size) {
        if (size) buffer[0] = '\0';
        return 0;
    }
    buffer[out.length] = '\0';
    return out.length;
}
