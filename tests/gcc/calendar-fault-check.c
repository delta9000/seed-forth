#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
static long seconds, nanoseconds, status;
static int calls, wrong;
static char *zone="UTC0";
static char *test_getenv(const char *name)
{
    if (strcmp(name,"TZ")) wrong=1;
    return zone;
}
static long test_syscall(long number,long a,long b,long c,long d,long e,long f)
{
    long *value;
    calls++;
    if (number!=228 || a || !b || c || d || e || f) wrong=1;
    if (status==0) {
        value=(long *)b;value[0]=seconds;value[1]=nanoseconds;
    }
    return status;
}
#define __seed_syscall6 test_syscall
#define getenv test_getenv
#define time test_time
#define localtime test_localtime
#include "../../runtime/gcc-seed/calendar.c"
static int check_time(long s,long ns,long raw,long expected,int error)
{
    time_t stored, result;
    seconds=s;nanoseconds=ns;status=raw;calls=0;wrong=0;
    stored=17;errno=71;result=time(&stored);
    if (result!=expected || errno!=error || calls!=1 || wrong) return 0;
    if (stored!=expected) return 0;
    errno=0;calls=0;result=time(NULL);
    return result==expected && errno==((raw==0 && ns>=0 && ns<1000000000L)?0:error) && calls==1 && !wrong;
}
static int check_zone(char *text)
{
    time_t stamp;
    struct tm copy;
    struct tm *prior;
    zone="UTC0";stamp=0;prior=localtime(&stamp);
    if (!prior) return 0;
    copy=*prior;zone=text;stamp=86400;errno=71;
    return !localtime(&stamp) && errno==EINVAL && !memcmp(&copy,prior,sizeof(copy));
}
int main(void)
{
    int error;
    time_t stamp;
    struct tm *first, *second;
    struct tm saved;
    if (sizeof(struct tm)!=36 || sizeof(time_t)!=8) return 1;
    if (!check_time(-1,0,0,-1,71) || !check_time(0,999999999,0,0,71)
        || !check_time(LONG_MIN,1,0,LONG_MIN,71)
        || !check_time(LONG_MAX,1,0,LONG_MAX,71)) return 2;
    for (error=1;error<=4095;error++) if (!check_time(0,0,-error,-1,error)) return 3;
    if (!check_time(0,-1,0,-1,EIO) || !check_time(0,1000000000,0,-1,EIO)
        || !check_time(0,0,1,-1,EIO) || !check_time(0,0,-4096,-1,EIO)
        || !check_time(0,0,LONG_MIN,-1,EIO)) return 4;
    if (!check_zone(NULL) || !check_zone("") || !check_zone("UTC")
        || !check_zone("GMT") || !check_zone("GMT0") || !check_zone("UTC1")
        || !check_zone("America/New_York") || !check_zone(":UTC0")
        || !check_zone("UTC0 ") || !check_zone("UTC0DST")) return 5;
    zone="UTC0";stamp=0;errno=71;first=localtime(&stamp);
    if (!first || errno!=71) return 6;
    saved=*first;errno=71;
    if (localtime(NULL) || errno!=EINVAL || memcmp(first,&saved,sizeof(saved))) return 7;
    stamp=LONG_MIN;errno=71;
    if (localtime(&stamp) || errno!=EOVERFLOW || memcmp(first,&saved,sizeof(saved))) return 8;
    stamp=LONG_MAX;errno=71;
    if (localtime(&stamp) || errno!=EOVERFLOW || memcmp(first,&saved,sizeof(saved))) return 9;
    stamp=86400;errno=0;second=localtime(&stamp);
    if (second!=first || second->tm_mday!=2 || errno!=0) return 10;
    puts("calendar fault checks passed");return 0;
}
