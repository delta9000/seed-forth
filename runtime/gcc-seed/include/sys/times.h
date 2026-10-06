#ifndef SEED_GCC_SYS_TIMES_H
#define SEED_GCC_SYS_TIMES_H
/* Original seed-forth interface; see LICENSE and ../../SYSINFO.md.
   Process times in clock ticks of sysconf(_SC_CLK_TCK) (100 on Linux). */
#include <sys/types.h>
#ifndef SEED_CLOCK_T_DEFINED
#define SEED_CLOCK_T_DEFINED
typedef long clock_t;
#endif
struct tms {
    clock_t tms_utime;
    clock_t tms_stime;
    clock_t tms_cutime;
    clock_t tms_cstime;
};
/* Returns ticks since an arbitrary point; (clock_t)-1 only on EFAULT. */
clock_t times(struct tms *buffer);
#endif
