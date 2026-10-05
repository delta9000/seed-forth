/* Scripted syscall double for this test; never a production provider. */
#include <unistd.h>
#include <errno.h>
#include <seed-syscall.h>
static int calls;
static int invalid;
static long answer;
long __seed_syscall6(long number,long a1,long a2,long a3,long a4,long a5,long a6)
{
    int i;
    calls++;
    if (number != 16 || a1 != 37 || a2 != 0x5401 || a3 == 0 || a4 || a5 || a6) invalid = 1;
    for (i = 0; i < 36; i++) ((unsigned char *)a3)[i] = (unsigned char)i;
    return answer;
}
int main(void)
{
    answer = 0; errno = EDOM;
    if (isatty(37) != 1 || errno != EDOM || calls != 1) return 1;
    answer = -EINTR;
    if (isatty(37) || errno != EINTR || calls != 2) return 2;
    answer = -ENOTTY;
    if (isatty(37) || errno != ENOTTY || calls != 3) return 3;
    answer = -EBADF;
    if (isatty(37) || errno != EBADF || calls != 4) return 4;
    return invalid ? 5 : 0;
}
