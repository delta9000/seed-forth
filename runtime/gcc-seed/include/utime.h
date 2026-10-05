#ifndef SEED_GCC_UTIME_H
#define SEED_GCC_UTIME_H
/* Original seed-forth declarations; see LICENSE and ../FILE-METADATA.md.
   Linux AMD64 utime syscall record: two signed 64-bit second counts. */
#include <sys/types.h>
struct utimbuf {
    time_t actime;
    time_t modtime;
};
/* NULL sets both times to the current time. Whole seconds only. */
int utime(const char *path, const struct utimbuf *times);
#endif
