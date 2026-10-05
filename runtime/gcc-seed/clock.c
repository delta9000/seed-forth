/* Original seed-forth implementation; see LICENSE. Linux AMD64 LP64. */
#include <time.h>
#include <limits.h>
#include <errno.h>
#include <seed-syscall.h>
struct seed_clock_timespec {
    long seconds;
    long nanoseconds;
};
clock_t clock(void)
{
    struct seed_clock_timespec value;
    long result;
    long fraction;
    /* CLOCK_PROCESS_CPUTIME_ID includes every thread's CPU use, not sleep
       or waited-for children. This raw syscall never modifies errno. */
    result = __seed_syscall6(228, 2, (long)&value, 0, 0, 0, 0);
    if (result < 0) { errno = (int)-result; return (clock_t)-1; }
    if (result != 0 || value.seconds < 0 || value.nanoseconds < 0
        || value.nanoseconds >= 1000000000L) {
        errno = EIO;
        return (clock_t)-1;
    }
    fraction = value.nanoseconds / 1000;
    /* Check both multiplication and addition before doing either. */
    if (value.seconds > LONG_MAX / CLOCKS_PER_SEC
        || (value.seconds == LONG_MAX / CLOCKS_PER_SEC
            && fraction > LONG_MAX % CLOCKS_PER_SEC)) {
        errno = EOVERFLOW;
        return (clock_t)-1;
    }
    return value.seconds * CLOCKS_PER_SEC + fraction;
}
