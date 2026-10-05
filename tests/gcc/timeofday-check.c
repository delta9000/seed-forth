/* gettimeofday contracts. "facts" prints deterministic results that must
   match host GCC/glibc byte for byte; "now" prints one reading for the
   driver's cross-process window checks. The host oracle routes only the
   NULL-time and invalid-pointer cases through the raw syscall: glibc declares
   the time pointer nonnull, and its vDSO path faults in user space instead of
   returning EFAULT. This runtime forwards those cases to the kernel. */
#include <sys/time.h>
#include <time.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#ifdef TIMEOFDAY_HOST_ORACLE
#include <unistd.h>
#include <sys/syscall.h>
static int kernel_only_call(struct timeval *now, void *zone)
{
    return (int)syscall(SYS_gettimeofday, now, zone);
}
#else
#define kernel_only_call gettimeofday
#endif

struct zone_record { int minutes_west; int dst_kind; };

static long micros(struct timeval *value)
{
    return value->tv_sec * 1000000L + value->tv_usec;
}

int main(int argc, char **argv)
{
    struct timeval value;
    struct timeval previous;
    struct zone_record zone;
    struct zone_record again;
    time_t before;
    time_t after;
    int result;
    int i;
    if (argc != 2) return 2;
    if (strcmp(argv[1], "now") == 0) {
        if (gettimeofday(&value, NULL) != 0) return 3;
        printf("%ld %ld\n", (long)value.tv_sec, (long)value.tv_usec);
        return 0;
    }
    if (strcmp(argv[1], "facts") != 0) return 4;
    /* Success returns zero, fills a normalized record and preserves errno. */
    errno = 1234;
    before = time(NULL);
    result = gettimeofday(&value, NULL);
    after = time(NULL);
    printf("null-zone result=%d errno=%d\n", result, errno);
    printf("usec-range %d\n", value.tv_usec >= 0 && value.tv_usec < 1000000L);
    printf("within-time %d\n", before <= value.tv_sec && value.tv_sec <= after);
    /* Consecutive readings do not decrease (no clock step expected meanwhile). */
    previous = value;
    result = 1;
    for (i = 0; i < 2000; i++) {
        if (gettimeofday(&value, NULL) != 0 || micros(&value) < micros(&previous)) result = 0;
        previous = value;
    }
    printf("nondecreasing %d\n", result);
    /* Both pointers may be NULL. */
    errno = 55;
    result = kernel_only_call(NULL, NULL);
    printf("both-null result=%d errno=%d\n", result, errno);
    /* A nonnull zone receives the kernel's record (values compared with host). */
    zone.minutes_west = -12345;
    zone.dst_kind = -12345;
    result = gettimeofday(&value, &zone);
    again.minutes_west = -1;
    again.dst_kind = -1;
    kernel_only_call(NULL, &again);
    printf("zone result=%d minutes_west=%d dst=%d stable=%d\n", result, zone.minutes_west,
           zone.dst_kind, zone.minutes_west == again.minutes_west && zone.dst_kind == again.dst_kind);
    /* Invalid pointers are reported by the kernel as EFAULT. */
    errno = 0;
    result = kernel_only_call((struct timeval *)8, NULL);
    printf("bad-time result=%d errno=%d\n", result, errno);
    errno = 0;
    result = kernel_only_call(&value, (void *)8);
    printf("bad-zone result=%d errno=%d\n", result, errno);
    return 0;
}
