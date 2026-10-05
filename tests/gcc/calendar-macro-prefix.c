/* Harness prefix for an exact extracted original libcpp switch block.
   The test script inserts the pinned original monthnames and cases. */
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
static long chosen_seconds, chosen_status;
static int time_calls, localtime_calls, allocations, warnings;
static char *chosen_zone="UTC0";
static char *fixture_getenv(const char *name)
{
    if (strcmp(name,"TZ")) return NULL;
    return chosen_zone;
}
static long fixture_syscall(long number,long a,long b,long c,long d,long e,long f)
{
    long *value;
    if (number!=228 || a || !b || c || d || e || f) return -EINVAL;
    if (chosen_status) return chosen_status;
    value=(long *)b;value[0]=chosen_seconds;value[1]=0;return 0;
}
#define __seed_syscall6 fixture_syscall
#define getenv fixture_getenv
#define time fixture_time
#define localtime fixture_localtime
/* CALENDAR_SOURCE_INCLUDE */
#undef time
#undef localtime
static time_t counted_time(time_t *pointer)
{
    time_calls++;return fixture_time(pointer);
}
static struct tm *counted_localtime(const time_t *pointer)
{
    localtime_calls++;return fixture_localtime(pointer);
}
#define time counted_time
#define localtime counted_localtime
#define U (const unsigned char *)
#define BT_DATE 1
#define BT_TIME 2
#define CPP_DL_WARNING 1
typedef struct { const unsigned char *date; const unsigned char *time; } cpp_reader;
typedef struct { struct { int builtin; } value; } cpp_hashnode;
static unsigned char *blocks[2];
static unsigned char *_cpp_unaligned_alloc(cpp_reader *pfile,size_t length)
{
    unsigned char *value;
    (void)pfile;
    if (allocations>=2) exit(90);
    value=malloc(length+1);
    if (!value) exit(91);
    blocks[allocations]=value;
    allocations++;value[length]=85;
    return value;
}
static void cpp_errno(cpp_reader *pfile,int severity,const char *message)
{
    (void)pfile;(void)severity;
    if (strcmp(message,"could not determine date and time")) exit(92);
    warnings++;
}
