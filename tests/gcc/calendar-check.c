#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#ifdef HOST_ORACLE
#include <unistd.h>
#define __seed_syscall6 syscall
#else
#include <seed-syscall.h>
#endif
struct kernel_timespec { long seconds; long nanoseconds; };
static int live(void)
{
    struct kernel_timespec before, after;
    time_t sample, stored;
    struct tm *value;
    int i, sample_errno;
    for (i=0;i<32;i++) {
#ifdef HOST_ORACLE
        /* Compare libc time() with its own possibly coarse clock basis.
           The Forth branch retains strict raw CLOCK_REALTIME bounds. */
        before.seconds=time(NULL);
#else
        if (__seed_syscall6(228,0,(long)&before,0,0,0,0)) return 1;
#endif
        stored=17;errno=71;sample=time(&stored);sample_errno=errno;
#ifdef HOST_ORACLE
        after.seconds=time(NULL);
#else
        if (__seed_syscall6(228,0,(long)&after,0,0,0,0)) return 2;
#endif
        if (sample<before.seconds || sample>after.seconds || sample!=stored
            || sample_errno!=71) return 3;
        value=localtime(&sample);
        if (!value || value->tm_mon<0 || value->tm_mon>11
            || value->tm_mday<1 || value->tm_mday>31
            || value->tm_wday<0 || value->tm_wday>6 || value->tm_isdst!=0) return 4;
    }
    puts("live wall-clock checks passed");return 0;
}
int main(int argc,char **argv)
{
    time_t stamp;
    struct tm *value;
    int i;
    if (sizeof(time_t)!=8 || (time_t)-1>=0) return 10;
    if (argc==2 && strcmp(argv[1],"live")==0) return live();
    for (i=1;i<argc;i++) {
        stamp=atol(argv[i]);errno=71;value=localtime(&stamp);
        if (!value) printf("error %d\n",errno);
        else printf("%d %d %d %d %d %d %d %d %d %d\n",
            value->tm_sec,value->tm_min,value->tm_hour,value->tm_mday,
            value->tm_mon,value->tm_year,value->tm_wday,value->tm_yday,
            value->tm_isdst,errno);
    }
    return 0;
}
