#ifndef SEED_GCC_SYS_TIME_H
#define SEED_GCC_SYS_TIME_H
/* Bounded Linux AMD64 record definitions; see CALENDAR.md.
   No gettimeofday, interval timer, select, or timezone APIs are declared. */
#include <sys/types.h>
typedef long suseconds_t;
struct timeval {
    time_t tv_sec;
    suseconds_t tv_usec;
};
#endif
