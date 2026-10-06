#ifndef SEED_GCC_TIMESPEC_H
#define SEED_GCC_TIMESPEC_H
/* Private: struct timespec for time.h, sys/stat.h and sys/time.h.
   Linux AMD64 layout: signed 64-bit seconds and nanoseconds. */
#include <sys/types.h>
struct timespec {
    time_t tv_sec;
    long tv_nsec;
};
#endif
