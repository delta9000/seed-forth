/* Forth-built renamed copies isolate forced raw-syscall results from production. */
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
int tested_fcntl(int, int, ...);
static long result, number, args[6];
static int calls;
long tested_fcntl_syscall(long n, long a, long b, long c, long d, long e, long f)
{
    ++calls;
    number = n;
    args[0] = a; args[1] = b; args[2] = c;
    args[3] = d; args[4] = e; args[5] = f;
    return result;
}
static void prepare(long value)
{
    result = value;
    calls = 0;
    number = -1;
    errno = 777;
}
static int sent(int fd, int command, long argument)
{
    return calls == 1 && number == 72 && args[0] == fd && args[1] == command
        && args[2] == argument && args[3] == 0 && args[4] == 0 && args[5] == 0;
}
int main(void)
{
    static const int unsupported[] = { 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
        36, 37, 38, 1024, 1025, 1026, 1031, 1032, 1033, 1034, -1, 99999 };
    unsigned int i;
    /* Commands without an argument always forward zero. */
    prepare(1);
    if (tested_fcntl(4, F_GETFD) != 1 || !sent(4, F_GETFD, 0) || errno != 777) return 1;
    prepare(0x8802);
    if (tested_fcntl(5, F_GETFL, (void *)-1) != 0x8802 || !sent(5, F_GETFL, 0) || errno != 777) return 2;
    /* One int argument, sign-extended to the long syscall argument. */
    prepare(0);
    if (tested_fcntl(6, F_SETFD, FD_CLOEXEC) != 0 || !sent(6, F_SETFD, 1) || errno != 777) return 3;
    prepare(0);
    if (tested_fcntl(7, F_SETFL, O_NONBLOCK | O_APPEND) != 0 || !sent(7, F_SETFL, 3072)) return 4;
    prepare(12);
    if (tested_fcntl(8, F_DUPFD, 3) != 12 || !sent(8, F_DUPFD, 3)) return 5;
    prepare(-22);
    if (tested_fcntl(8, F_DUPFD, -1) != -1 || !sent(8, F_DUPFD, -1L) || errno != EINVAL) return 6;
    prepare(30);
    if (tested_fcntl(-1, F_DUPFD_CLOEXEC, 30) != 30 || !sent(-1, 1030, 30)) return 7;
    /* Exact Linux error window; -4096 is not an error encoding. */
    prepare(-9);
    if (tested_fcntl(9, F_GETFD) != -1 || errno != EBADF || calls != 1) return 8;
    prepare(-4095);
    if (tested_fcntl(9, F_GETFL) != -1 || errno != 4095) return 9;
    prepare(-4096);
    if (tested_fcntl(9, F_GETFL) != -4096 || errno != 777) return 10;
    prepare(-4);
    if (tested_fcntl(9, F_SETFL, 0) != -1 || errno != EINTR || calls != 1) return 11;
    /* Unsupported commands: EINVAL, no syscall, no argument interpretation. */
    for (i = 0; i < sizeof(unsupported) / sizeof(unsupported[0]); i++) {
        prepare(0);
        if (tested_fcntl(3, unsupported[i], (void *)0) != -1 || errno != EINVAL || calls) return 20;
    }
    printf("fcntl fault contracts passed\n");
    return 0;
}
