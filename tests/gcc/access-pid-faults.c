/* Injection is test-only: check syscall arguments and the Linux errno band. */
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
int tested_access(const char *, int);
pid_t tested_getpid(void);
static long answer;
static long arguments[7];
static int calls;
long measured_fake(long n, long a, long b, long c, long d, long e, long f)
{
    calls++;
    arguments[0] = n; arguments[1] = a; arguments[2] = b;
    arguments[3] = c; arguments[4] = d; arguments[5] = e; arguments[6] = f;
    return answer;
}
#define CHECK(x) do { if (!(x)) { printf("fault failure %d\n", __LINE__); return 1; } } while (0)
int main(void)
{
    int i;
    int before;
    int mode;
    int (*permission)(const char *, int) = tested_access;
    pid_t (*process)(void) = tested_getpid;
    for (i = 1; i <= 4095; i++) {
        answer = -i; errno = 777; before = calls;
        CHECK(permission((const char *)0x7fff12345678UL, 7) == -1);
        CHECK(errno == i && calls == before + 1);
        CHECK(arguments[0] == 21 && arguments[1] == 0x7fff12345678L && arguments[2] == 7);
        CHECK(arguments[3] == 0 && arguments[4] == 0 && arguments[5] == 0 && arguments[6] == 0);
    }
    for (i = 0; i < 32; i++) {
        mode = (int)(1U << i); answer = 0; errno = 777; before = calls;
        CHECK(permission((const char *)0xffff800012345678UL, mode) == 0);
        CHECK(errno == 777 && calls == before + 1);
        CHECK((unsigned long)arguments[1] == 0xffff800012345678UL && arguments[2] == (long)mode);
    }
    answer = -4096; errno = 777;
    CHECK(permission(0, -1) == -4096 && errno == 777 && arguments[2] == -1);
    for (i = 1; i < 100; i++) {
        answer = i; errno = 777; before = calls;
        CHECK(process() == i && errno == 777 && calls == before + 1);
        CHECK(arguments[0] == 39);
        CHECK(arguments[1] == 0 && arguments[2] == 0 && arguments[3] == 0);
        CHECK(arguments[4] == 0 && arguments[5] == 0 && arguments[6] == 0);
    }
    answer = 2147483647; errno = 777;
    CHECK(process() == 2147483647 && errno == 777);
    CHECK(sizeof(pid_t) == 4 && (pid_t)-1 < 0);
    puts("access/getpid injected contracts passed");
    return 0;
}
