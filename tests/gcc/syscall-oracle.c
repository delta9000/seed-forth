/* Interoperability oracle only: the host toolchain does not build the bridge. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

extern long __seed_syscall6(long, long, long, long, long, long, long);

int main(void)
{
    int fds[2];
    char in[] = "forth syscall bridge", out[sizeof in];
    FILE *backing;
    long mapped;
    unsigned char marker = 173;
    unsigned char *page;
    if (__seed_syscall6(SYS_getpid, 0, 0, 0, 0, 0, 0) != getpid()) return 1;
    errno = 123;
    if (__seed_syscall6(SYS_close, -1, 0, 0, 0, 0, 0) != -EBADF) return 2;
    if (errno != 123) return 3;
    if (__seed_syscall6(-1, 0, 0, 0, 0, 0, 0) != -ENOSYS) return 4;
    if (pipe(fds)) return 5;
    if (__seed_syscall6(SYS_write, fds[1], (long)in, sizeof in, 0, 0, 0)
        != (long)sizeof in) return 6;
    if (__seed_syscall6(SYS_read, fds[0], (long)out, sizeof out, 0, 0, 0)
        != (long)sizeof out) return 7;
    if (memcmp(in, out, sizeof in)) return 8;
    if (__seed_syscall6(SYS_close, fds[0], 0, 0, 0, 0, 0)) return 9;
    if (__seed_syscall6(SYS_close, fds[1], 0, 0, 0, 0, 0)) return 10;

    /* A nonzero file offset exercises the seventh C argument on the stack,
       independently of the four earlier register-to-register shuffles. */
    backing = tmpfile();
    if (!backing || ftruncate(fileno(backing), 8192)) return 11;
    if (pwrite(fileno(backing), &marker, 1, 4096) != 1) return 12;
    mapped = __seed_syscall6(SYS_mmap, 0, 4096, PROT_READ | PROT_WRITE,
                            MAP_PRIVATE, fileno(backing), 4096);
    if ((unsigned long)mapped >= (unsigned long)-4095) return 13;
    page = (unsigned char *)mapped;
    if (page[0] != marker || page[4095] != 0) return 14;
    page[4095] = 93;
    if (__seed_syscall6(SYS_munmap, mapped, 4096, 0, 0, 0, 0)) return 15;
    if (fclose(backing)) return 16;
    puts("PASS: Forth-built syscall bridge, raw errors and six arguments");
    return 0;
}
