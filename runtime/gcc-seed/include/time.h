#ifndef SEED_GCC_TIME_H
#define SEED_GCC_TIME_H
/* Bounded Linux AMD64 time interfaces; see CLOCK-REMOVE.md and CALENDAR.md. */
#include <sys/types.h>
#ifndef SEED_CLOCK_T_DEFINED
#define SEED_CLOCK_T_DEFINED
typedef long clock_t;
#endif
#define CLOCKS_PER_SEC 1000000L
clock_t clock(void);
/* Standard nine-int layout; no host-libc extension fields. */
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
/* Requires explicit TZ=UTC0; unsupported/missing zones fail with EINVAL. */
struct tm *localtime(const time_t *timer);
/* UTC for any zone; shares localtime's static record. See ../CALENDAR.md. */
struct tm *gmtime(const time_t *timer);
/* asctime text of localtime(timer) in a static buffer; NULL when it fails. */
char *ctime(const time_t *timer);
/* Bounded C-locale subset: %Y %m %d %e %H %M %S %j %y %F %T %z %%. */
size_t strftime(char *out, size_t size, const char *format, const struct tm *time);
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
