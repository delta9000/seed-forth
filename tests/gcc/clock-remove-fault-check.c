#include <errno.h>
#include <limits.h>
#include <stdio.h>
static long seconds, nanoseconds, clock_result, unlink_result, rmdir_result;
static int calls, wrong;
static const char *wanted_path;
static long test_syscall(long number,long a,long b,long c,long d,long e,long f)
{
    long *value;
    calls++;
    if (c || d || e || f) wrong=1;
    if (number==228) {
        if (a!=2 || b==0) wrong=1;
        if (clock_result==0) { value=(long *)b;value[0]=seconds;value[1]=nanoseconds; }
        return clock_result;
    }
    if ((const char *)a!=wanted_path || b) wrong=1;
    if (number==87) return unlink_result;
    if (number==84) return rmdir_result;
    wrong=1;return -ENOSYS;
}
#define __seed_syscall6 test_syscall
#define clock test_clock
#define remove test_remove
#include "../../runtime/gcc-seed/clock.c"
#include "../../runtime/gcc-seed/remove.c"
static int check_clock(long s,long ns,long raw,long wanted,int error)
{
    long value;
    seconds=s;nanoseconds=ns;clock_result=raw;calls=0;wrong=0;errno=71;
    value=clock();
    return value==wanted && errno==error && calls==1 && !wrong;
}
static int check_remove(long unlink_value,long rmdir_value,int wanted,int error,int count)
{
    int value;
    unlink_result=unlink_value;rmdir_result=rmdir_value;calls=0;wrong=0;errno=71;
    wanted_path="retained-pointer";value=remove(wanted_path);
    return value==wanted && errno==error && calls==count && !wrong;
}
int main(void)
{
    int error;
    if (sizeof(clock_t)!=8 || CLOCKS_PER_SEC!=1000000L) return 1;
    if (E2BIG!=7 || ENOTDIR!=20 || EISDIR!=21 || ENOTEMPTY!=39) return 2;
    if (!check_clock(0,0,0,0,71) || !check_clock(0,999,0,0,71)
        || !check_clock(0,1000,0,1,71) || !check_clock(2,999999999,0,2999999,71)) return 3;
    if (!check_clock(9223372036854L,775807999,0,LONG_MAX,71)
        || !check_clock(9223372036854L,775808000,0,-1,EOVERFLOW)
        || !check_clock(9223372036855L,0,0,-1,EOVERFLOW)
        || !check_clock(LONG_MAX,0,0,-1,EOVERFLOW)) return 4;
    if (!check_clock(-1,0,0,-1,EIO) || !check_clock(0,-1,0,-1,EIO)
        || !check_clock(0,1000000000,0,-1,EIO) || !check_clock(0,0,1,-1,EIO)) return 5;
    for(error=1;error<=4095;error++) if(!check_clock(0,0,-error,-1,error))return 6;
    if(!check_remove(0,-EIO,0,71,1) || !check_remove(-EISDIR,0,0,71,2))return 7;
    for(error=1;error<=4095;error++) {
        if(error!=EISDIR && !check_remove(-error,0,-1,error,1))return 8;
        if(!check_remove(-EISDIR,-error,-1,error,2))return 9;
    }
    puts("clock/remove fault checks passed");return 0;
}
