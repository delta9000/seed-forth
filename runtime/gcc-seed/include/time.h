#ifndef SEED_GCC_TIME_H
#define SEED_GCC_TIME_H
/* Bounded Linux AMD64 time interfaces; see CLOCK-REMOVE.md and CALENDAR.md. */
#include <sys/types.h>
typedef long clock_t;
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
#endif
