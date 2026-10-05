#include <sys/time.h>
#include <time.h>
#include <stddef.h>
long seed_calendar_abi(int index)
{
    if (index==0) return sizeof(struct tm);
    if (index==1) return offsetof(struct tm,tm_sec);
    if (index==2) return offsetof(struct tm,tm_min);
    if (index==3) return offsetof(struct tm,tm_hour);
    if (index==4) return offsetof(struct tm,tm_mday);
    if (index==5) return offsetof(struct tm,tm_mon);
    if (index==6) return offsetof(struct tm,tm_year);
    if (index==7) return offsetof(struct tm,tm_wday);
    if (index==8) return offsetof(struct tm,tm_yday);
    if (index==9) return offsetof(struct tm,tm_isdst);
    if (index==10) return sizeof(time_t);
    if (index==11) return sizeof(struct timeval);
    if (index==12) return offsetof(struct timeval,tv_usec);
    if (index==13) return (time_t)-1>=0;
    return -1;
}
