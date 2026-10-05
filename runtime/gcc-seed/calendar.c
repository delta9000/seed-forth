/* Original seed-forth implementation; see LICENSE. Linux AMD64 LP64. */
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
#include <stdio.h>
#include <seed-syscall.h>

struct seed_calendar_timespec {
    long seconds;
    long nanoseconds;
};

time_t time(time_t *result)
{
    struct seed_calendar_timespec value;
    long status;
    /* CLOCK_REALTIME status is separate from seconds: timestamp -1 is valid. */
    status = __seed_syscall6(228, 0, (long)&value, 0, 0, 0, 0);
    if (status >= -4095 && status < 0) {
        errno = (int)-status;
        if (result) *result = (time_t)-1;
        return (time_t)-1;
    }
    if (status != 0 || value.nanoseconds < 0
        || value.nanoseconds >= 1000000000L) {
        errno = EIO;
        if (result) *result = (time_t)-1;
        return (time_t)-1;
    }
    if (result) *result = value.seconds;
    return value.seconds;
}

static struct tm seed_calendar_result;
static int seed_calendar_leap(long year)
{
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

/* Proleptic Gregorian UTC conversion shared by localtime and gmtime.
   Returns 0, or an errno value with *result unchanged. */
static int seed_calendar_convert(time_t timer, struct tm *result)
{
    struct tm value;
    long days;
    long seconds;
    long cycles;
    long year;
    long weekday;
    int length;
    int month;
    static const int month_lengths[12] = {
        31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
    };
    days = timer / 86400L;
    seconds = timer % 86400L;
    if (seconds < 0) {
        seconds += 86400L;
        days--;
    }
    value.tm_hour = (int)(seconds / 3600);
    value.tm_min = (int)((seconds % 3600) / 60);
    value.tm_sec = (int)(seconds % 60);
    weekday = (days + 4) % 7;
    if (weekday < 0) weekday += 7;
    value.tm_wday = (int)weekday;
    /* 2000-01-01 is 10957 days after the Epoch. Gregorian leap patterns
       repeat every 400 years (146097 days), including negative years.
       Divide first, then walk at most 399 years and eleven months. */
    days -= 10957L;
    cycles = days / 146097L;
    days %= 146097L;
    if (days < 0) {
        days += 146097L;
        cycles--;
    }
    year = 2000L + cycles * 400L;
    length = 365 + seed_calendar_leap(year);
    while (days >= length) {
        days -= length;
        year++;
        length = 365 + seed_calendar_leap(year);
    }
    if (year - 1900L < INT_MIN || year - 1900L > INT_MAX) return EOVERFLOW;
    value.tm_year = (int)(year - 1900L);
    value.tm_yday = (int)days;
    month = 0;
    length = month_lengths[month];
    while (days >= length) {
        days -= length;
        month++;
        length = month_lengths[month];
        if (month == 1 && seed_calendar_leap(year)) length++;
    }
    value.tm_mon = month;
    value.tm_mday = (int)days + 1;
    value.tm_isdst = 0;
    *result = value;
    return 0;
}

struct tm *localtime(const time_t *timer)
{
    const char *zone;
    int error;
    /* The bootstrap profile requires an explicit, unambiguous fixed zone.
       Missing TZ does not authorize assuming the machine's local zone. */
    zone = getenv("TZ");
    if (!timer || !zone || strcmp(zone, "UTC0") != 0) {
        errno = EINVAL;
        return NULL;
    }
    error = seed_calendar_convert(*timer, &seed_calendar_result);
    if (error) {
        errno = error;
        return NULL;
    }
    return &seed_calendar_result;
}

/* UTC needs no zone; it shares the static record with localtime. */
struct tm *gmtime(const time_t *timer)
{
    int error;
    if (!timer) {
        errno = EINVAL;
        return NULL;
    }
    error = seed_calendar_convert(*timer, &seed_calendar_result);
    if (error) {
        errno = error;
        return NULL;
    }
    return &seed_calendar_result;
}

static const char seed_calendar_days[7][4] = {
    "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
};
static const char seed_calendar_months[12][4] = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

/* asctime layout "Thu Jan  1 00:00:00 1970\n" of localtime(timer), in a
   static buffer; NULL with localtime's errno when that fails. Years are
   printed with %d, so the buffer holds any int year. */
char *ctime(const time_t *timer)
{
    static char text[64];
    struct tm *value = localtime(timer);
    if (!value) return NULL;
    sprintf(text, "%s %s%3d %.2d:%.2d:%.2d %ld\n",
            seed_calendar_days[value->tm_wday], seed_calendar_months[value->tm_mon],
            value->tm_mday, value->tm_hour, value->tm_min, value->tm_sec,
            value->tm_year + 1900L);
    return text;
}

/* Append LENGTH bytes; 0 when they and the final NUL do not fit. */
static int seed_calendar_put(char *out, size_t size, size_t *used,
                             const char *text, size_t length)
{
    if (length >= size - *used) return 0;
    memcpy(out + *used, text, length);
    *used += length;
    return 1;
}

/* Bounded C-locale strftime: %Y %m %d %e %H %M %S %j %y %F %T %z %%.
   Fields are taken from TIME without normalization; %z is +0000 because
   only UTC records exist. Any other conversion, a field outside its
   range, or output that does not fit returns 0 (EINVAL for the first two). */
size_t strftime(char *out, size_t size, const char *format, const struct tm *time)
{
    char field[32];
    size_t used = 0;
    long year;
    if (size == 0) return 0;
    if (!time || time->tm_mon < 0 || time->tm_mon > 11 || time->tm_mday < 1
        || time->tm_mday > 31 || time->tm_hour < 0 || time->tm_hour > 23
        || time->tm_min < 0 || time->tm_min > 59 || time->tm_sec < 0
        || time->tm_sec > 60 || time->tm_yday < 0 || time->tm_yday > 365) {
        errno = EINVAL;
        out[0] = '\0';
        return 0;
    }
    year = time->tm_year + 1900L;
    for (; *format; format++) {
        if (*format != '%') {
            field[0] = *format;
            field[1] = '\0';
        } else {
            format++;
            switch (*format) {
            case 'Y': sprintf(field, "%ld", year); break;
            case 'y': sprintf(field, "%.2ld", (year % 100 + 100) % 100); break;
            case 'm': sprintf(field, "%.2d", time->tm_mon + 1); break;
            case 'd': sprintf(field, "%.2d", time->tm_mday); break;
            case 'e': sprintf(field, "%2d", time->tm_mday); break;
            case 'H': sprintf(field, "%.2d", time->tm_hour); break;
            case 'M': sprintf(field, "%.2d", time->tm_min); break;
            case 'S': sprintf(field, "%.2d", time->tm_sec); break;
            case 'j': sprintf(field, "%.3d", time->tm_yday + 1); break;
            case 'F':
                sprintf(field, "%ld-%.2d-%.2d", year, time->tm_mon + 1, time->tm_mday);
                break;
            case 'T':
                sprintf(field, "%.2d:%.2d:%.2d", time->tm_hour, time->tm_min, time->tm_sec);
                break;
            case 'z': strcpy(field, "+0000"); break;
            case '%': strcpy(field, "%"); break;
            default:
                errno = EINVAL;
                out[0] = '\0';
                return 0;
            }
        }
        if (!seed_calendar_put(out, size, &used, field, strlen(field))) {
            out[0] = '\0';
            return 0;
        }
    }
    out[used] = '\0';
    return used;
}
