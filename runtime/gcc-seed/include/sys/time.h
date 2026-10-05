#ifndef SEED_GCC_SYS_TIME_H
#define SEED_GCC_SYS_TIME_H
/* Bounded Linux AMD64 record definitions; see CALENDAR.md and PROCFS.md.
   No interval timer, select, settimeofday or struct timezone is declared. */
#include <sys/types.h>
typedef long suseconds_t;
struct timeval {
    time_t tv_sec;
    suseconds_t tv_usec;
};
/* Linux syscall 96. A nonnull zone pointer receives the kernel's two-int
   timezone record unchanged; NULL skips it. */
int gettimeofday(struct timeval *now, void *zone);
#endif
