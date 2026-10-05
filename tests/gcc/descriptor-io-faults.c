/* Forth-built copies isolate forced raw-syscall results from production. */
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
int tested_open(const char *, int, ...);
ssize_t tested_read(int, void *, size_t);
int tested_close(int);
off_t tested_lseek(int, off_t, int);
static long result, number, args[6];
static int calls;
long tested_descriptor_syscall(long n, long a, long b, long c, long d, long e, long f)
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
    errno = 777;
}
static int tail_zero(void)
{
    return args[3] == 0 && args[4] == 0 && args[5] == 0;
}
int main(void)
{
    char path[] = "name", buffer[8];
    mode_t mode = 0x800001a4U;
    prepare(0);
    if (tested_open(path, O_RDONLY) != 0 || calls != 1 || number != 2
        || args[0] != (long)path || args[1] != O_RDONLY || args[2] != 0
        || !tail_zero() || errno != 777) return 1;
    prepare(31);
    if (tested_open(path, O_CREAT | O_RDWR, mode) != 31 || calls != 1
        || args[1] != (O_CREAT | O_RDWR) || args[2] != 2147484068L
        || !tail_zero() || errno != 777) return 2;
    prepare(32);
    if (tested_open(path, O_CREAT | O_WRONLY, 0600) != 32
        || args[2] != 0600 || calls != 1) return 3;
    prepare(33);
    if (tested_open(path, O_TMPFILE | O_RDWR, (mode_t)0642) != 33
        || args[1] != (O_TMPFILE | O_RDWR) || args[2] != 0642 || calls != 1) return 4;
    prepare(34);
    if (tested_open(path, O_DIRECTORY) != 34 || args[2] != 0 || calls != 1) return 5;
    prepare(-EINTR);
    if (tested_open(path, O_RDONLY) != -1 || errno != EINTR || calls != 1) return 6;
    prepare(0);
    if (tested_open(path, O_CREAT | 0x40000000) != -1 || errno != EINVAL || calls) return 7;
    prepare(0);
    if (tested_open(path, 4194304 | O_RDWR) != -1 || errno != EINVAL || calls) return 8;
    prepare(0);
    if (tested_open(path, O_ACCMODE) != -1 || errno != EINVAL || calls) return 9;
    prepare(3);
    if (tested_read(0, buffer, 8) != 3 || calls != 1 || number != 0
        || args[0] != 0 || args[1] != (long)buffer || args[2] != 8
        || !tail_zero() || errno != 777) return 10;
    prepare(0);
    if (tested_read(4, buffer, 0) != 0 || args[2] != 0 || calls != 1 || errno != 777) return 11;
    prepare(-EINTR);
    if (tested_read(4, buffer, 8) != -1 || errno != EINTR || calls != 1) return 12;
    prepare(-EFAULT);
    if (tested_read(-1, buffer, (size_t)-1) != -1 || errno != EFAULT
        || args[0] != -1 || args[2] != -1 || calls != 1) return 13;
    prepare(-4095);
    if (tested_read(4, buffer, 8) != -1 || errno != 4095 || calls != 1) return 14;
    prepare(-4096);
    if (tested_read(4, buffer, 8) != -4096 || errno != 777 || calls != 1) return 15;
    prepare(0);
    if (tested_close(0) || calls != 1 || number != 3 || args[0] != 0
        || args[1] || args[2] || !tail_zero() || errno != 777) return 16;
    prepare(-EINTR);
    if (tested_close(9) != -1 || errno != EINTR || calls != 1) return 17;
    prepare(-EIO);
    if (tested_close(9) != -1 || errno != EIO || calls != 1) return 18;
    prepare(-EBADF);
    if (tested_close(-1) != -1 || errno != EBADF || args[0] != -1 || calls != 1) return 19;
    prepare(4294967301L);
    if (tested_lseek(5, -4294967301L, SEEK_END) != 4294967301L || calls != 1
        || number != 8 || args[0] != 5 || args[1] != -4294967301L
        || args[2] != SEEK_END || !tail_zero() || errno != 777) return 20;
    prepare(-ESPIPE);
    if (tested_lseek(5, 0, SEEK_CUR) != -1 || errno != ESPIPE || calls != 1) return 21;
    prepare(-4095);
    if (tested_lseek(5, 0, SEEK_SET) != -1 || errno != 4095 || calls != 1) return 22;
    prepare(-4096);
    if (tested_lseek(5, 0, SEEK_SET) != -4096 || errno != 777 || calls != 1) return 23;
    prepare(-4095);
    if (tested_open(path, O_RDONLY) != -1 || errno != 4095 || calls != 1) return 24;
    prepare(-4096);
    if (tested_open(path, O_RDONLY) != -4096 || errno != 777 || calls != 1) return 25;
    prepare(-4095);
    if (tested_close(5) != -1 || errno != 4095 || calls != 1) return 26;
    prepare(-4096);
    if (tested_close(5) != -4096 || errno != 777 || calls != 1) return 27;
    puts("descriptor I/O fault contracts passed");
    return 0;
}
