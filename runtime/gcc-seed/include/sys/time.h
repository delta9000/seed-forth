#ifndef SEED_GCC_SYS_TIME_H
#define SEED_GCC_SYS_TIME_H
/* Bounded Linux AMD64 record definitions; see CALENDAR.md and PROCFS.md.
   No interval timer or select is declared; see ../../SYSINFO.md. */
#include <sys/types.h>
typedef long suseconds_t;
struct timeval {
    time_t tv_sec;
    suseconds_t tv_usec;
};
/* Linux syscall 96. A nonnull zone pointer receives the kernel's two-int
   timezone record unchanged; NULL skips it. */
int gettimeofday(struct timeval *now, void *zone);
/* The kernel's (obsolete) two-int zone record. */
struct timezone {
    int tz_minuteswest;
    int tz_dsttime;
};
/* Linux syscall 164; requires CAP_SYS_TIME. ZONE may be NULL. */
int settimeofday(const struct timeval *now, const struct timezone *zone);
/* Access and modification times with microseconds; NULL means now.
   See ../../FILE-CALLS.md. */
int utimes(const char *path, const struct timeval times[2]);
#endif
