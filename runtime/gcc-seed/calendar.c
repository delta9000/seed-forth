/* Original seed-forth implementation; see LICENSE and CALENDAR.md.
   Linux AMD64 LP64. Wall clock, proleptic Gregorian conversion, POSIX TZ
   rules, localtime/gmtime/mktime/timegm, asctime/ctime and difftime.
   strftime lives in strftime.c and reads the zone through
   __seed_calendar_zone below. Single-threaded: the static records and the
   cached zone are shared by every caller. */
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

/* ------------------------------------------------------------------ */
/* Proleptic Gregorian arithmetic on absolute (astronomical) years.    */

static int seed_calendar_leap(long year)
{
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

/* Days before month M (0..12) of a common [0] or leap [1] year. */
static const short seed_calendar_before[2][13] = {
    { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365 },
    { 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366 }
};

static long seed_calendar_floor(long value, long divisor)
{
    long quotient = value / divisor;
    if (value % divisor < 0) quotient--;
    return quotient;
}

/* Days from 1970-01-01 to January 1 of YEAR; exact for |YEAR| < 2^50.
   The leap counts up to 1969 (492, 19 and 4) cancel at 1970. */
static long seed_calendar_jan1(long year)
{
    return 365L * (year - 1970)
        + (seed_calendar_floor(year - 1, 4) - 492)
        - (seed_calendar_floor(year - 1, 100) - 19)
        + (seed_calendar_floor(year - 1, 400) - 4);
}

/* Seconds since the Epoch of YEAR (tm_year base), day of year YDAY and a
   time of day, all unnormalized. Exact for any int fields plus a month
   carry: the magnitude stays below 2^58. */
static long seed_calendar_seconds(long year, long yday, long hour, long minute,
                                  long second)
{
    long days = seed_calendar_jan1(year + 1900) + yday;
    return ((days * 24 + hour) * 60 + minute) * 60 + second;
}

/* Break TIMER + OFFSET (seconds east of UTC, |OFFSET| < 2^40) into
   *RESULT with tm_isdst 0. Returns 0, or EOVERFLOW with *RESULT unchanged
   when the year does not fit tm_year. */
static int seed_calendar_convert(time_t timer, long offset, struct tm *result)
{
    struct tm value;
    long days;
    long seconds;
    long cycles;
    long year;
    long guess;
    long weekday;
    int leap;
    int month;
    days = timer / 86400L;
    seconds = timer % 86400L;
    /* Adding the offset to the remainder cannot overflow, unlike TIMER. */
    seconds += offset % 86400L;
    days += offset / 86400L;
    while (seconds < 0) {
        seconds += 86400L;
        days--;
    }
    while (seconds >= 86400L) {
        seconds -= 86400L;
        days++;
    }
    value.tm_hour = (int)(seconds / 3600);
    value.tm_min = (int)((seconds % 3600) / 60);
    value.tm_sec = (int)(seconds % 60);
    weekday = (days + 4) % 7;
    if (weekday < 0) weekday += 7;
    value.tm_wday = (int)weekday;
    /* 2000-01-01 is 10957 days after the Epoch and starts a 400-year
       (146097-day) cycle. Inside a cycle, days/366 never overestimates
       the year and is at most three years short. */
    days -= 10957L;
    cycles = days / 146097L;
    days %= 146097L;
    if (days < 0) {
        days += 146097L;
        cycles--;
    }
    guess = days / 366;
    while (365L * (guess + 1) + (guess + 4) / 4 - (guess + 100) / 100
           + (guess + 400) / 400 <= days)
        guess++;
    days -= 365L * guess + (guess + 3) / 4 - (guess + 99) / 100
        + (guess + 399) / 400;
    year = 2000L + cycles * 400L + guess;
    if (year - 1900L < INT_MIN || year - 1900L > INT_MAX) return EOVERFLOW;
    value.tm_year = (int)(year - 1900L);
    value.tm_yday = (int)days;
    leap = seed_calendar_leap(year);
    month = 0;
    while (days >= seed_calendar_before[leap][month + 1]) month++;
    value.tm_mon = month;
    value.tm_mday = (int)(days - seed_calendar_before[leap][month]) + 1;
    value.tm_isdst = 0;
    *result = value;
    return 0;
}

/* ------------------------------------------------------------------ */
/* POSIX TZ: std offset [dst [offset] [,start[/time],end[/time]]].     */

#define SEED_TZ_NAME 64
#define SEED_TZ_TEXT 256
#define SEED_TZ_JULIAN1 1
#define SEED_TZ_JULIAN0 2
#define SEED_TZ_MONTH 3

struct seed_tz_rule {
    int kind;
    long day;
    long month;
    long week;
    long weekday;
    long seconds;
};

struct seed_tz_zone {
    char names[2][SEED_TZ_NAME];
    long gmtoff[2];
    int rules;
    struct seed_tz_rule rule[2];
};

char *tzname[2] = { "UTC", "UTC" };
long timezone = 0;
int daylight = 0;

static struct seed_tz_zone seed_tz;
static int seed_tz_cached;
static int seed_tz_was_unset;
static char seed_tz_text[SEED_TZ_TEXT];

static int seed_tz_alpha(int c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static int seed_tz_digit(int c)
{
    return c >= '0' && c <= '9';
}

/* One "%hu" scanf conversion: optional white space and sign, then at least
   one digit. The value wraps to 16 bits; a huge magnitude saturates first,
   as strtoul does. */
static int seed_tz_number(const char **text, long *value)
{
    const char *p = *text;
    unsigned long result = 0;
    int negative = 0;
    int saturated = 0;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\v' || *p == '\f'
           || *p == '\r')
        p++;
    if (*p == '+' || *p == '-') negative = *p++ == '-';
    if (!seed_tz_digit(*p)) return 0;
    while (seed_tz_digit(*p)) {
        if (result > 1000000000000000UL) saturated = 1;
        else result = result * 10 + (unsigned long)(*p - '0');
        p++;
    }
    if (saturated) result = 65535;
    else if (negative) result = 0 - result;
    *value = (long)(result & 65535UL);
    *text = p;
    return 1;
}

/* hh[:mm[:ss]] as sscanf "%hu%n:%hu%n:%hu%n" consumes it; fields that are
   absent keep their callers' defaults. */
static int seed_tz_clock(const char **text, long *hours, long *minutes,
                         long *seconds)
{
    const char *p = *text;
    const char *q;
    if (!seed_tz_number(&p, hours)) return 0;
    q = p;
    if (*q == ':') {
        q++;
        if (seed_tz_number(&q, minutes)) {
            p = q;
            if (*q == ':') {
                q++;
                if (seed_tz_number(&q, seconds)) p = q;
            }
        }
    }
    *text = p;
    return 1;
}

/* Alphabetic name of at least three letters, or <...> holding at least
   three letters, digits, '+' or '-'. */
static int seed_tz_name(const char **text, char *name)
{
    const char *p = *text;
    const char *start = p;
    long length = 0;
    while (seed_tz_alpha(p[length])) length++;
    if (length >= 3) {
        p += length;
    } else {
        if (*p != '<') return 0;
        start = ++p;
        length = 0;
        while (seed_tz_alpha(p[length]) || seed_tz_digit(p[length])
               || p[length] == '+' || p[length] == '-')
            length++;
        if (p[length] != '>' || length < 3) return 0;
        p += length + 1;
    }
    if (length >= SEED_TZ_NAME) return 0;
    memcpy(name, start, (size_t)length);
    name[length] = '\0';
    *text = p;
    return 1;
}

/* [+-]hh[:mm[:ss]] west of UTC (hours capped at 24, minutes and seconds
   at 59), stored as seconds east. A missing DST offset is one hour ahead
   of standard time. */
static int seed_tz_offset(const char **text, int dst, struct seed_tz_zone *zone)
{
    const char *p = *text;
    long sign = -1;
    long hours = 0;
    long minutes = 0;
    long seconds = 0;
    if (!dst && *p != '+' && *p != '-' && !seed_tz_digit(*p)) return 0;
    if (*p == '+' || *p == '-') sign = *p++ == '-' ? 1 : -1;
    if (seed_tz_clock(&p, &hours, &minutes, &seconds)) {
        if (hours > 24) hours = 24;
        if (minutes > 59) minutes = 59;
        if (seconds > 59) seconds = 59;
        zone->gmtoff[dst] = sign * (hours * 3600 + minutes * 60 + seconds);
    } else if (!dst) {
        return 0;
    } else {
        zone->gmtoff[1] = zone->gmtoff[0] + 3600;
    }
    *text = p;
    return 1;
}

/* Jn, n or Mm.w.d with an optional /[-]hh[:mm[:ss]] (default 02:00; the
   hours are not capped, so -167..167 and beyond work). An empty rule is
   the US default M3.2.0 (start) or M11.1.0 (end). */
static int seed_tz_rule_parse(const char **text, int which,
                              struct seed_tz_rule *rule)
{
    const char *p = *text;
    long hours = 2;
    long minutes = 0;
    long seconds = 0;
    int negative = 0;
    if (*p == ',') p++;
    if (*p == 'J' || seed_tz_digit(*p)) {
        unsigned long day = 0;
        rule->kind = *p == 'J' ? SEED_TZ_JULIAN1 : SEED_TZ_JULIAN0;
        if (*p == 'J' && !seed_tz_digit(*++p)) return 0;
        while (seed_tz_digit(*p)) {
            if (day <= 1000) day = day * 10 + (unsigned long)(*p - '0');
            p++;
        }
        if (day > 365 || (rule->kind == SEED_TZ_JULIAN1 && day == 0)) return 0;
        rule->day = (long)day;
    } else if (*p == 'M') {
        p++;
        rule->kind = SEED_TZ_MONTH;
        if (!seed_tz_number(&p, &rule->month) || *p++ != '.'
            || !seed_tz_number(&p, &rule->week) || *p++ != '.'
            || !seed_tz_number(&p, &rule->weekday))
            return 0;
        if (rule->month < 1 || rule->month > 12 || rule->week < 1
            || rule->week > 5 || rule->weekday > 6)
            return 0;
    } else if (*p == '\0') {
        rule->kind = SEED_TZ_MONTH;
        rule->month = which ? 11 : 3;
        rule->week = which ? 1 : 2;
        rule->weekday = 0;
    } else {
        return 0;
    }
    if (*p != '\0' && *p != '/' && *p != ',') return 0;
    if (*p == '/') {
        p++;
        if (*p == '\0') return 0;
        negative = *p == '-';
        if (negative) p++;
        seed_tz_clock(&p, &hours, &minutes, &seconds);
    }
    rule->seconds = (negative ? -1 : 1) * (hours * 3600 + minutes * 60 + seconds);
    *text = p;
    return 1;
}

/* 0 when no standard name and offset parse. A malformed daylight part
   leaves standard time only. */
static int seed_tz_parse(const char *text, struct seed_tz_zone *zone)
{
    const char *p = text;
    memset(zone, 0, sizeof *zone);
    if (!seed_tz_name(&p, zone->names[0]) || !seed_tz_offset(&p, 0, zone))
        return 0;
    zone->gmtoff[1] = zone->gmtoff[0];
    strcpy(zone->names[1], zone->names[0]);
    if (*p == '\0') return 1;
    if (seed_tz_name(&p, zone->names[1])) {
        seed_tz_offset(&p, 1, zone);
        if (seed_tz_rule_parse(&p, 0, &zone->rule[0])
            && seed_tz_rule_parse(&p, 1, &zone->rule[1])) {
            zone->rules = 1;
            return 1;
        }
    }
    zone->gmtoff[1] = zone->gmtoff[0];
    strcpy(zone->names[1], zone->names[0]);
    return 1;
}

static void seed_tz_fixed(struct seed_tz_zone *zone, const char *name)
{
    memset(zone, 0, sizeof *zone);
    strcpy(zone->names[0], name);
    strcpy(zone->names[1], name);
}

/* Reread TZ; reparse only when its text changed. */
static void seed_tz_load(void)
{
    const char *text = getenv("TZ");
    size_t length;
    if (seed_tz_cached) {
        if (!text && seed_tz_was_unset) return;
        if (text && !seed_tz_was_unset && strcmp(text, seed_tz_text) == 0) return;
    }
    if (!text || *text == '\0' || *text == ':') {
        /* No host /etc/localtime or zoneinfo file is ever read. */
        seed_tz_fixed(&seed_tz, "UTC");
    } else if (!seed_tz_parse(text, &seed_tz)) {
        seed_tz_fixed(&seed_tz, strcmp(text, "GMT") == 0 ? "GMT" : "UTC");
    }
    tzname[0] = seed_tz.names[0];
    tzname[1] = seed_tz.rules ? seed_tz.names[1] : seed_tz.names[0];
    timezone = -seed_tz.gmtoff[0];
    daylight = seed_tz.gmtoff[0] != seed_tz.gmtoff[1];
    seed_tz_cached = 0;
    length = text ? strlen(text) : 0;
    if (length < SEED_TZ_TEXT) {
        seed_tz_was_unset = text == NULL;
        if (text) memcpy(seed_tz_text, text, length + 1);
        seed_tz_cached = 1;
    }
}

void tzset(void)
{
    seed_tz_load();
}

/* Name and seconds east of UTC for standard (ISDST 0) or daylight time
   (ISDST > 0) in the current TZ; used by strftime's %z and %Z. */
const char *__seed_calendar_zone(int isdst, long *gmtoff)
{
    int which = isdst > 0;
    seed_tz_load();
    if (gmtoff) *gmtoff = seed_tz.gmtoff[which];
    return tzname[which];
}

/* Wrap to 32-bit two's complement, like the reference int day count. */
static long seed_tz_int32(long value)
{
    value &= 0xffffffffL;
    if (value >= 0x80000000L) value -= 0x100000000L;
    return value;
}

/* Transition instant of RULE in absolute YEAR. Years up to 1970 use the
   1970-01-01 base, as glibc does, which keeps every earlier instant on the
   standard side of a northern rule and the daylight side of a southern
   one. The weekday of the month's first day uses Zeller's congruence. */
static long seed_tz_change(const struct seed_tz_rule *rule, long gmtoff, long year)
{
    long t = 0;
    int leap = seed_calendar_leap(year);
    if (year > 1970) {
        long days = (year - 1970) * 365 + ((year - 1) / 4 - 1970 / 4)
            - ((year - 1) / 100 - 1970 / 100) + ((year - 1) / 400 - 1970 / 400);
        t = seed_tz_int32(days) * 86400L;
    }
    if (rule->kind == SEED_TZ_JULIAN1) {
        t += (rule->day - 1) * 86400L;
        if (rule->day >= 60 && leap) t += 86400L;
    } else if (rule->kind == SEED_TZ_JULIAN0) {
        t += rule->day * 86400L;
    } else {
        long shifted = (rule->month + 9) % 12 + 1;
        long base = seed_tz_int32(rule->month <= 2 ? year - 1 : year);
        long century = base / 100;
        long within = base % 100;
        long first = seed_tz_int32((26 * shifted - 2) / 10 + 1 + within
                                   + within / 4 + century / 4 - 2 * century) % 7;
        long length = seed_calendar_before[leap][rule->month]
            - seed_calendar_before[leap][rule->month - 1];
        long day;
        long week;
        if (first < 0) first += 7;
        day = rule->weekday - first;
        if (day < 0) day += 7;
        for (week = 1; week < rule->week; week++) {
            if (day + 7 >= length) break;
            day += 7;
        }
        t += (seed_calendar_before[leap][rule->month - 1] + day) * 86400L;
    }
    return t - gmtoff + rule->seconds;
}

/* Daylight flag for TIMER, decided by the rules of TIMER's UTC year. */
static int seed_tz_isdst(time_t timer, long utc_year)
{
    long start;
    long end;
    if (!seed_tz.rules) return 0;
    start = seed_tz_change(&seed_tz.rule[0], seed_tz.gmtoff[0], utc_year);
    end = seed_tz_change(&seed_tz.rule[1], seed_tz.gmtoff[1], utc_year);
    if (start > end) return timer < end || timer >= start;
    return timer >= start && timer < end;
}

/* Local conversion with the zone already loaded; 0 or an errno value. */
static int seed_calendar_local(time_t timer, struct tm *result)
{
    struct tm value;
    int error;
    int isdst;
    error = seed_calendar_convert(timer, 0, &value);
    if (error) return error;
    isdst = seed_tz_isdst(timer, value.tm_year + 1900L);
    error = seed_calendar_convert(timer, seed_tz.gmtoff[isdst], &value);
    if (error) return error;
    value.tm_isdst = isdst;
    *result = value;
    return 0;
}

static struct tm seed_calendar_result;

struct tm *localtime_r(const time_t *timer, struct tm *result)
{
    int error;
    if (!timer || !result) {
        errno = EINVAL;
        return NULL;
    }
    seed_tz_load();
    error = seed_calendar_local(*timer, result);
    if (error) {
        errno = error;
        return NULL;
    }
    return result;
}

struct tm *localtime(const time_t *timer)
{
    return localtime_r(timer, &seed_calendar_result);
}

struct tm *gmtime_r(const time_t *timer, struct tm *result)
{
    int error;
    if (!timer || !result) {
        errno = EINVAL;
        return NULL;
    }
    error = seed_calendar_convert(*timer, 0, result);
    if (error) {
        errno = error;
        return NULL;
    }
    return result;
}

/* UTC for any zone; shares the static record with localtime. */
struct tm *gmtime(const time_t *timer)
{
    return gmtime_r(timer, &seed_calendar_result);
}

/* ------------------------------------------------------------------ */
/* mktime and timegm invert the conversion by probing, like glibc.     */

static int seed_mktime_convert(int local, long timer, struct tm *result)
{
    int error = local ? seed_calendar_local(timer, result)
                      : seed_calendar_convert(timer, 0, result);
    if (error) {
        errno = error;
        return 0;
    }
    return 1;
}

/* Floor average without overflow. */
static long seed_mktime_average(long a, long b)
{
    long half_a = (a & 1) ? (a - 1) / 2 : a / 2;
    long half_b = (b & 1) ? (b - 1) / 2 : b / 2;
    return half_a + half_b + ((a | b) & 1);
}

/* Convert *TIMER; if that overflows, bisect toward 0 for the in-range
   instant nearest to it and store that in *TIMER. */
static int seed_mktime_ranged(int local, long *timer, struct tm *result)
{
    long bad;
    long ok = 0;
    long middle;
    int found = 0;
    struct tm best;
    if (seed_mktime_convert(local, *timer, result)) return 1;
    if (errno != EOVERFLOW) return 0;
    bad = *timer;
    memset(&best, 0, sizeof best);
    for (;;) {
        middle = seed_mktime_average(ok, bad);
        if (middle == ok || middle == bad) break;
        if (seed_mktime_convert(local, middle, result)) {
            ok = middle;
            best = *result;
            found = 1;
        } else if (errno != EOVERFLOW) {
            return 0;
        } else {
            bad = middle;
        }
    }
    if (!found) return 0;
    *timer = ok;
    *result = best;
    return 1;
}

static long seed_mktime_diff(long year, long yday, long hour, long minute,
                             long second, const struct tm *value)
{
    return seed_calendar_seconds(year, yday, hour, minute, second)
        - seed_calendar_seconds(value->tm_year, value->tm_yday, value->tm_hour,
                                value->tm_min, value->tm_sec);
}

static int seed_mktime_add(long a, long b, long *sum)
{
    if ((b > 0 && a > LONG_MAX - b) || (b < 0 && a < LONG_MIN - b)) return 0;
    *sum = a + b;
    return 1;
}

/* Previous result minus the requested fields read as UTC: the first guess
   of the next call, as in glibc (so results inside a spring-forward gap
   depend on the previous call in the same way). */
static long seed_mktime_offset_local;
static long seed_mktime_offset_utc;

static time_t seed_mktime(struct tm *request, int local, long *offset)
{
    struct tm value;
    struct tm other;
    long second = request->tm_sec;
    long minute = request->tm_min;
    long hour = request->tm_hour;
    long month = request->tm_mon;
    int isdst = request->tm_isdst;
    long remainder = month % 12;
    long year = (long)request->tm_year + month / 12;
    long yday;
    long requested_second = second;
    long t, t1, t2, dt, adjust;
    int probes = 6;
    if (remainder < 0) {
        remainder += 12;
        year--;
    }
    yday = seed_calendar_before[seed_calendar_leap(year + 1900)][remainder]
        - 1 + (long)request->tm_mday;
    if (second < 0) second = 0;
    if (second > 59) second = 59;
    t = seed_calendar_seconds(year, yday, hour, minute, second) + *offset;
    t1 = t2 = t;
    for (;;) {
        if (!seed_mktime_ranged(local, &t, &value)) return -1;
        dt = seed_mktime_diff(year, yday, hour, minute, second, &value);
        if (dt == 0) break;
        /* Oscillating between two instants: a spring-forward gap. */
        if (t == t1 && t != t2
            && (isdst < 0 ? value.tm_isdst != 0
                          : (isdst != 0) != (value.tm_isdst != 0)))
            goto found;
        if (--probes == 0) {
            errno = EOVERFLOW;
            return -1;
        }
        t1 = t2;
        t2 = t;
        if (!seed_mktime_add(t, dt, &t)) t = dt > 0 ? LONG_MAX : LONG_MIN;
    }
    if (isdst >= 0 && (isdst == 0) != (value.tm_isdst == 0)) {
        /* The requested daylight flag differs: borrow the offset of the
           nearest instant having it (601200-second steps, earlier first,
           up to 229222800 seconds away), else assume a one-hour shift. */
        long delta;
        int direction;
        int difference = (isdst == 0) - (value.tm_isdst == 0);
        for (delta = 601200; delta < 229222800L; delta += 601200) {
            for (direction = -1; direction <= 1; direction += 2) {
                long probe;
                long guess;
                if (!seed_mktime_add(t, delta * direction, &probe)) continue;
                if (!seed_mktime_ranged(local, &probe, &other)) return -1;
                if ((isdst == 0) != (other.tm_isdst == 0)) continue;
                if (!seed_mktime_add(probe,
                                     seed_mktime_diff(year, yday, hour, minute,
                                                      second, &other), &guess))
                    continue;
                if (seed_mktime_convert(local, guess, &value)) {
                    t = guess;
                    goto found;
                }
                if (errno != EOVERFLOW) return -1;
            }
        }
        if (!seed_mktime_add(t, 3600L * difference, &t)
            || !seed_mktime_convert(local, t, &value)) {
            errno = EOVERFLOW;
            return -1;
        }
    }
found:
    *offset = t - seed_calendar_seconds(year, yday, hour, minute, second);
    if (requested_second != value.tm_sec) {
        /* Out-of-range seconds were clamped above; add them back. */
        adjust = (second == 0 && value.tm_sec == 60) - second + requested_second;
        if (!seed_mktime_add(t, adjust, &t)) {
            errno = EOVERFLOW;
            return -1;
        }
        if (!seed_mktime_convert(local, t, &value)) return -1;
    }
    *request = value;
    return t;
}

time_t mktime(struct tm *value)
{
    if (!value) {
        errno = EINVAL;
        return -1;
    }
    seed_tz_load();
    return seed_mktime(value, 1, &seed_mktime_offset_local);
}

time_t timegm(struct tm *value)
{
    if (!value) {
        errno = EINVAL;
        return -1;
    }
    value->tm_isdst = 0;
    return seed_mktime(value, 0, &seed_mktime_offset_utc);
}

/* ------------------------------------------------------------------ */
/* asctime, ctime, difftime.                                          */

static const char seed_calendar_days[7][4] = {
    "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
};
static const char seed_calendar_months[12][4] = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

/* Append VALUE with at least DIGITS digits (zero filled after the sign),
   right aligned in WIDTH columns; returns the new end. */
static char *seed_calendar_number(char *out, long value, int digits, int width)
{
    char text[24];
    int length = 0;
    int negative = value < 0;
    unsigned long magnitude = negative ? 0 - (unsigned long)value : (unsigned long)value;
    do {
        text[length++] = (char)('0' + magnitude % 10);
        magnitude /= 10;
    } while (magnitude);
    while (length < digits) text[length++] = '0';
    if (negative) text[length++] = '-';
    while (width-- > length) *out++ = ' ';
    while (length) *out++ = text[--length];
    return out;
}

/* "%.3s %.3s%3d %.2d:%.2d:%.2d %d\n" with "???" for unknown names. NULL and
   EOVERFLOW when the year is not an int or the text needs LIMIT bytes. */
static char *seed_calendar_asctime(const struct tm *value, char *out, long limit)
{
    char text[128];
    char *end = text;
    const char *name;
    if (!value) {
        errno = EINVAL;
        return NULL;
    }
    if (value->tm_year > INT_MAX - 1900) {
        errno = EOVERFLOW;
        return NULL;
    }
    name = value->tm_wday < 0 || value->tm_wday > 6 ? "???"
        : seed_calendar_days[value->tm_wday];
    memcpy(end, name, 3);
    end += 3;
    *end++ = ' ';
    name = value->tm_mon < 0 || value->tm_mon > 11 ? "???"
        : seed_calendar_months[value->tm_mon];
    memcpy(end, name, 3);
    end += 3;
    end = seed_calendar_number(end, value->tm_mday, 1, 3);
    *end++ = ' ';
    end = seed_calendar_number(end, value->tm_hour, 2, 0);
    *end++ = ':';
    end = seed_calendar_number(end, value->tm_min, 2, 0);
    *end++ = ':';
    end = seed_calendar_number(end, value->tm_sec, 2, 0);
    *end++ = ' ';
    end = seed_calendar_number(end, value->tm_year + 1900L, 1, 0);
    *end++ = '\n';
    *end = '\0';
    if (end - text >= limit) {
        errno = EOVERFLOW;
        return NULL;
    }
    memcpy(out, text, (size_t)(end - text) + 1);
    return out;
}

char *asctime(const struct tm *value)
{
    static char text[128];
    return seed_calendar_asctime(value, text, (long)sizeof text);
}

/* The caller's buffer holds 26 bytes, as C and POSIX specify. */
char *asctime_r(const struct tm *value, char *buffer)
{
    return seed_calendar_asctime(value, buffer, 26);
}

/* asctime(localtime(timer)): NULL with localtime's errno when it fails. */
char *ctime(const time_t *timer)
{
    struct tm *value = localtime(timer);
    if (!value) return NULL;
    return asctime(value);
}

char *ctime_r(const time_t *timer, char *buffer)
{
    struct tm value;
    if (!localtime_r(timer, &value)) return NULL;
    return asctime_r(&value, buffer);
}

/* Exact difference rounded once to double. */
double difftime(time_t end, time_t start)
{
    unsigned long magnitude;
    int negative = end < start;
    double result;
    magnitude = negative ? (unsigned long)start - (unsigned long)end
                         : (unsigned long)end - (unsigned long)start;
    if (magnitude <= (unsigned long)LONG_MAX) {
        result = (double)(long)magnitude;
    } else {
        /* Halve with a sticky low bit, so that only one rounding occurs. */
        result = (double)(long)((magnitude >> 1) | (magnitude & 1)) * 2.0;
    }
    return negative ? -result : result;
}
