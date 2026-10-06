#ifndef SEED_GCC_TIME_H
#define SEED_GCC_TIME_H
/* Linux AMD64 time interfaces; see ../CLOCK-REMOVE.md and ../CALENDAR.md. */
#include <sys/types.h>
#ifndef SEED_CLOCK_T_DEFINED
#define SEED_CLOCK_T_DEFINED
typedef long clock_t;
#endif
#define CLOCKS_PER_SEC 1000000L
clock_t clock(void);
/* Standard nine-int layout; no tm_gmtoff or tm_zone extension fields. */
struct tm {
    int tm_sec;
    int tm_min;
    int tm_hour;
    int tm_mday;
    int tm_mon;
    int tm_year;
    int tm_wday;
    int tm_yday;
    int tm_isdst;
};
time_t time(time_t *result);
/* Zone from TZ as a POSIX string ("EST5EDT,M3.2.0,M11.1.0", "<+0530>-5:30").
   Unset, empty, ':'-prefixed or unparsable TZ means UTC; no zoneinfo file
   or /etc/localtime is ever read. localtime, localtime_r, mktime and
   strftime reread TZ; tzset sets tzname, timezone and daylight. */
extern char *tzname[2];
extern long timezone;
extern int daylight;
void tzset(void);
/* localtime and gmtime share one static record; NULL and EOVERFLOW when the
   year does not fit tm_year. */
struct tm *localtime(const time_t *timer);
struct tm *localtime_r(const time_t *timer, struct tm *result);
struct tm *gmtime(const time_t *timer);
struct tm *gmtime_r(const time_t *timer, struct tm *result);
/* Normalize out-of-range fields and invert localtime (mktime) or gmtime
   (timegm, which zeroes tm_isdst); -1 and EOVERFLOW when unrepresentable. */
time_t mktime(struct tm *value);
time_t timegm(struct tm *value);
/* "Thu Jan  1 00:00:00 1970\n"; the _r forms need 26-byte buffers. */
char *asctime(const struct tm *value);
char *asctime_r(const struct tm *value, char *buffer);
char *ctime(const time_t *timer);
char *ctime_r(const time_t *timer, char *buffer);
double difftime(time_t end, time_t start);
/* C-locale C99/POSIX conversions plus the GNU ones (%k %l %P %s ...),
   the flags _ - 0 ^ #, field widths, and ignored E/O modifiers. */
size_t strftime(char *out, size_t size, const char *format, const struct tm *value);
/* POSIX clocks and sleeping; see ../SYSINFO.md. */
#include <seed-timespec.h>
typedef int clockid_t;
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 1
#define CLOCK_PROCESS_CPUTIME_ID 2
#define CLOCK_THREAD_CPUTIME_ID 3
int clock_gettime(clockid_t clock, struct timespec *now);
int clock_getres(clockid_t clock, struct timespec *resolution);
/* One Linux call; after EINTR, a nonnull REMAINING gets the unslept time. */
int nanosleep(const struct timespec *request, struct timespec *remaining);
#endif
