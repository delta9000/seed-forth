/* Forth production and independent libc/ABI permission/process fixture. */
#include <unistd.h>
#include <sys/types.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
long __seed_syscall6(long, long, long, long, long, long, long);
#ifdef MEASURED_INTEROP
int tested_access(const char *, int);
pid_t tested_getpid(void);
#define permission tested_access
#define process tested_getpid
#else
#define permission access
#define process getpid
#endif
#define CHECK(x) do { if (!(x)) { printf("failure %d\n", __LINE__); return 1; } } while (0)
int main(int argc, char **argv)
{
    int i;
    int mode;
    int result;
    int error;
    int again;
    int (*check)(const char *, int) = permission;
    pid_t (*pid)(void) = process;
    pid_t actual;
    long area;
    char *page;
    char *tail;
    size_t length;
    CHECK(argc > 1 && sizeof(pid_t) == 4 && (pid_t)-1 < 0);
    CHECK(F_OK == 0 && X_OK == 1 && W_OK == 2 && R_OK == 4);
    errno = 777;
    actual = pid();
    CHECK(actual > 0 && actual == (pid_t)__seed_syscall6(39, 0, 0, 0, 0, 0, 0));
    CHECK(errno == 777);
    for (i = 0; i < 100; i++) CHECK(pid() == actual && errno == 777);
    area = __seed_syscall6(9, 0, 12288, 0, 34, -1, 0);
    CHECK(area > 0);
    page = (char *)(area + 4096);
    CHECK(__seed_syscall6(10, area + 4096, 4096, 3, 0, 0, 0) == 0);
    for (i = 1; i < argc; i++) {
        length = strlen(argv[i]) + 1;
        CHECK(length <= 4096);
        tail = page + 4096 - length;
        memcpy(tail, argv[i], length);
        CHECK(__seed_syscall6(10, area + 4096, 4096, 1, 0, 0, 0) == 0);
        for (mode = 0; mode <= 7; mode++) {
            errno = 777;
            result = check(argv[i], mode); error = errno;
            CHECK(result == 0 || result == -1);
            CHECK(result == -1 || error == 777);
            errno = 777; again = check(tail, mode);
            CHECK(again == result && errno == error);
            CHECK(memcmp(tail, argv[i], length) == 0);
            printf("path %d mode %d result %d errno %d\n", i, mode, result, error);
        }
        CHECK(__seed_syscall6(10, area + 4096, 4096, 3, 0, 0, 0) == 0);
    }
    /* Every invalid mode bit, including signed int's high bit, reaches Linux. */
    for (i = 3; i < 32; i++) {
        mode = (int)(1U << i); errno = 0;
        CHECK(check(argv[1], mode) == -1 && errno == EINVAL);
    }
    errno = 0; CHECK(check(argv[1], -1) == -1 && errno == EINVAL);
    errno = 0; CHECK(check((const char *)0, F_OK) == -1 && errno == EFAULT);
    errno = 0; CHECK(check((const char *)(area + 8192), F_OK) == -1 && errno == EFAULT);
    /* Kernel path copies terminate at NUL; no user-side string pre-scan. */
    page[4095] = 0; errno = 0;
    CHECK(check(page + 4095, F_OK) == -1 && errno == ENOENT);
    page[4095] = 'x'; errno = 0;
    CHECK(check(page + 4095, F_OK) == -1 && errno == EFAULT);
    memset(page, 'x', 4096); errno = 0;
    CHECK(check(page, F_OK) == -1 && errno == ENAMETOOLONG);
    CHECK(__seed_syscall6(11, area, 12288, 0, 0, 0, 0) == 0);
    puts("access/getpid real-kernel contracts passed");
    return 0;
}
