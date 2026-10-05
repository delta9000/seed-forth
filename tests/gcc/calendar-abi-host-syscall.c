/* Host-only syscall adapter: never linked into Forth production executables. */
#include <unistd.h>
#include <errno.h>
long __seed_syscall6(long number,long a,long b,long c,long d,long e,long f)
{
    long result;
    int saved;
    saved=errno;result=syscall(number,a,b,c,d,e,f);
    if (result==-1) result=-errno;
    errno=saved;return result;
}
