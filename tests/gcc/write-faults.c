#include <unistd.h>
#include <errno.h>
#include <stdio.h>
extern ssize_t tested_write(int, const void *, size_t);
static long response;
static int calls;
static int bad;
static const void *pointer;
static size_t length;
long tested_write_syscall(long n,long a,long b,long c,long d,long e,long f)
{
    calls++;
    if (n != 1 || a != 9 || b != (long)pointer || c != (long)length || d || e || f) bad = 1;
    return response;
}
int main(void)
{
    pointer = "example"; length = 7;
    response = 3; calls = 0; errno = EDOM;
    if (tested_write(9,pointer,length) != 3 || calls != 1 || errno != EDOM || bad) return 1;
    response = -EINTR; calls = 0;
    if (tested_write(9,pointer,length) != -1 || calls != 1 || errno != EINTR || bad) return 2;
    response = -ENOSPC; calls = 0;
    if (tested_write(9,pointer,length) != -1 || calls != 1 || errno != ENOSPC || bad) return 3;
    pointer = 0; length = 0; response = 0; calls = 0; errno = EDOM;
    if (tested_write(9,pointer,length) != 0 || calls != 1 || errno != EDOM || bad) return 4;
    puts("write fault contracts passed");
    return 0;
}
