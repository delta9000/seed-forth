/* Host headers/ABI are independent from the Forth runtime headers. */
#include <time.h>
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
struct seed_tm {
    int sec, min, hour, mday, mon, year, wday, yday, isdst;
};
extern long seed_time(long *result);
extern struct seed_tm *seed_localtime(const long *timer);
extern long seed_calendar_abi(int index);
int main(int argc,char **argv)
{
    long stamp, sample, stored;
    struct timespec before, after;
    struct seed_tm *a;
    struct tm *b;
    int i, sample_errno;
    if (sizeof(struct seed_tm)!=36 || seed_calendar_abi(0)!=36) return 1;
    for (i=1;i<=9;i++) if (seed_calendar_abi(i)!=(i-1)*4) return 2;
    if (seed_calendar_abi(10)!=8 || seed_calendar_abi(11)!=16
        || seed_calendar_abi(12)!=8 || seed_calendar_abi(13)!=0) return 3;
    /* Host time() may lag precise CLOCK_REALTIME at a second rollover. */
    if (clock_gettime(CLOCK_REALTIME,&before)) return 4;
    errno=71;sample=seed_time(&stored);sample_errno=errno;
    if (clock_gettime(CLOCK_REALTIME,&after)) return 4;
    if (sample<before.tv_sec || sample>after.tv_sec || stored!=sample
        || sample_errno!=71) return 4;
    for (i=1;i<argc;i++) {
        stamp=strtol(argv[i],NULL,10);errno=71;a=seed_localtime(&stamp);
        if (!a) {
            if (errno!=EOVERFLOW) return 5;
            b=localtime(&stamp);
            if (b || errno!=EOVERFLOW) return 6;
        } else {
            if (errno!=71) return 7;
            b=localtime(&stamp);
            if (!b || a->sec!=b->tm_sec || a->min!=b->tm_min
                || a->hour!=b->tm_hour || a->mday!=b->tm_mday
                || a->mon!=b->tm_mon || a->year!=b->tm_year
                || a->wday!=b->tm_wday || a->yday!=b->tm_yday
                || a->isdst!=b->tm_isdst) return 8;
        }
    }
    puts("calendar host ABI checks passed");return 0;
}
