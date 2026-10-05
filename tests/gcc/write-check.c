#include <unistd.h>
#include <errno.h>
#ifdef WRITE_HOST_ORACLE
static long __seed_syscall6(long n,long a,long b,long c,long d,long e,long f)
{
    long r = syscall(n,a,b,c,d,e,f);
    return r == -1 ? -errno : r;
}
#else
#include <seed-syscall.h>
#endif
static char bytes[8192];
int main(void)
{
    int descriptors[2];
    long flags;
    ssize_t result;
    int fills = 0;
    errno = EDOM;
    if (write(1, 0, 0) != 0 || errno != EDOM) return 1;
    if (write(-1, bytes, 1) != -1 || errno != EBADF) return 2;
    if (__seed_syscall6(22, (long)descriptors, 0, 0, 0, 0, 0)) return 3;
    flags = __seed_syscall6(72, descriptors[1], 3, 0, 0, 0, 0);
    if (flags < 0 || __seed_syscall6(72, descriptors[1], 4, flags | 2048, 0, 0, 0)) return 4;
    for (;;) {
        result = write(descriptors[1], bytes, 4096);
        if (result == -1) break;
        if (result != 4096 || ++fills > 10000) return 5;
    }
    if (errno != EAGAIN || fills == 0) return 6;
    if (__seed_syscall6(0, descriptors[0], (long)bytes, 4096, 0, 0, 0) != 4096) return 7;
    errno = EDOM;
    if (write(descriptors[1], bytes, sizeof(bytes)) != 4096 || errno != EDOM) return 8;
    if (__seed_syscall6(3, descriptors[0], 0, 0, 0, 0, 0)
        || __seed_syscall6(3, descriptors[1], 0, 0, 0, 0, 0)) return 9;
    if (write(1, "write contracts passed\n", 23) != 23) return 10;
    return 0;
}
