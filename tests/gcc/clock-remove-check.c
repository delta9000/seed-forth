#include <time.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#ifdef HOST_ORACLE
#include <unistd.h>
#define __seed_syscall6 syscall
#else
#include <seed-syscall.h>
#endif
struct kernel_timespec { long seconds; long nanoseconds; };
static long raw_cpu(void)
{
    struct kernel_timespec value;
    if(__seed_syscall6(228,2,(long)&value,0,0,0,0)!=0)return -1;
    return value.seconds*1000000L+value.nanoseconds/1000;
}
static int clock_checks(void)
{
    struct kernel_timespec delay;
    clock_t before, after, value;
    long low,high;
    volatile unsigned long accumulator=1;
    int i;
    if(sizeof(clock_t)!=8 || CLOCKS_PER_SEC!=1000000L)return 1;
    errno=71;low=raw_cpu();value=clock();high=raw_cpu();
    if(low<0 || value<low || value>high || errno!=71)return 2;
    before=clock();delay.seconds=0;delay.nanoseconds=100000000;
    if(__seed_syscall6(35,(long)&delay,0,0,0,0,0)!=0)return 3;
    after=clock();if(after<before || after-before>=50000)return 4;
    before=clock();
    for(i=0;i<4000000;i++)accumulator=accumulator*1664525UL+1013904223UL;
    after=clock();if(after<=before)return 5;
    printf("clock %ld %ld %lu\n",(long)value,(long)(after-before),accumulator);
    return 0;
}
int main(int argc,char **argv)
{
    int result;
    if(argc==2 && strcmp(argv[1],"clock")==0)return clock_checks();
    if(argc==3 && strcmp(argv[1],"remove")==0) {
        errno=71;result=remove(argv[2]);printf("%d %d\n",result,errno);return 0;
    }
    return 99;
}
