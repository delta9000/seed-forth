/* Original seed-forth implementation; see LICENSE. Linux AMD64 LP64. */
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
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

struct tm *localtime(const time_t *timer)
{
    struct tm value;
    const char *zone;
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
    /* The bootstrap profile requires an explicit, unambiguous fixed zone.
       Missing TZ does not authorize assuming the machine's local zone. */
    zone = getenv("TZ");
    if (!timer || !zone || strcmp(zone, "UTC0") != 0) {
        errno = EINVAL;
        return NULL;
    }
    days = *timer / 86400L;
    seconds = *timer % 86400L;
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
    if (year - 1900L < INT_MIN || year - 1900L > INT_MAX) {
        errno = EOVERFLOW;
        return NULL;
    }
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
    seed_calendar_result = value;
    return &seed_calendar_result;
}
