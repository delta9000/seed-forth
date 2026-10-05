/* Shared real-kernel fixture; host libc is a separate oracle executable. */
#include <sys/mman.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#ifdef MAPPING_HOST
long mapping_raw(long, long, long, long, long, long, long);
#else
#include <seed-syscall.h>
#define mapping_raw __seed_syscall6
#endif
#ifdef MAPPING_INTEROP
void *tested_mmap(void *, size_t, int, int, int, off_t);
int tested_munmap(void *, size_t);
#define mmap tested_mmap
#define munmap tested_munmap
#endif
#define CHECK(x) do { if (!(x)) { printf("failure %d errno %d\n", __LINE__, errno); return 1; } } while (0)

int main(int argc, char **argv)
{
    void *(*map_call)(void *, size_t, int, int, int, off_t);
    int (*unmap_call)(void *, size_t);
    char *p;
    char *q;
    char byte;
    unsigned char resident;
    int fd;
    int rw;
    int i;
    size_t lengths[7];
    off_t high = 4294971392L;
    map_call = mmap;
    unmap_call = munmap;
    CHECK(sizeof(size_t) == 8 && (size_t)-1 > 0);
    CHECK(sizeof(ssize_t) == 8 && (ssize_t)-1 < 0);
    CHECK(sizeof(off_t) == 8 && (off_t)-1 < 0);
    CHECK(sizeof(void *) == 8 && SSIZE_MAX == 9223372036854775807L);
    CHECK(PROT_NONE == 0 && PROT_READ == 1 && PROT_WRITE == 2);
    CHECK(MAP_PRIVATE == 2 && MAP_ANON == 32 && MAP_ANONYMOUS == 32);
    CHECK((unsigned long)MAP_FAILED == ~0UL);
    CHECK(argc == 2 || argc == 3);
    if (argc == 3) {
        p = map_call(0, 4096, argv[2][0] == 'n' ? PROT_NONE : PROT_READ,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        CHECK(p != MAP_FAILED);
        if (argv[2][0] == 'u') CHECK(unmap_call(p, 4096) == 0);
        if (argv[2][0] == 'r') *(volatile char *)p = 7;
        else byte = *(volatile char *)p;
        return 99;
    }
    lengths[0] = 1; lengths[1] = 4095; lengths[2] = 4096;
    lengths[3] = 4097; lengths[4] = 8191; lengths[5] = 8192; lengths[6] = 12289;
    for (i = 0; i < 7; i++) {
        errno = 123;
        p = map_call(0, lengths[i], PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANON, -1, 0);
        CHECK(p != MAP_FAILED && ((unsigned long)p & 4095) == 0 && errno == 123);
        CHECK(p[0] == 0 && p[lengths[i] - 1] == 0);
        p[0] = 17; p[lengths[i] - 1] = 39;
        CHECK(p[lengths[i] - 1] == 39);
        CHECK(unmap_call(p, lengths[i]) == 0 && errno == 123);
        CHECK(mapping_raw(27, (long)p, 4096, (long)&resident, 0, 0, 0) == -ENOMEM);
    }
    p = map_call(0, 12288, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    CHECK(p != MAP_FAILED);
    p[0] = 41; p[8192] = 43;
    CHECK(unmap_call(p + 4096, 1) == 0);
    CHECK(mapping_raw(27, (long)p, 4096, (long)&resident, 0, 0, 0) == 0);
    CHECK(mapping_raw(27, (long)(p + 4096), 4096, (long)&resident, 0, 0, 0) == -ENOMEM);
    CHECK(mapping_raw(27, (long)(p + 8192), 4096, (long)&resident, 0, 0, 0) == 0);
    CHECK(p[0] == 41 && p[8192] == 43);
    q = map_call(p + 1, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    CHECK(q != MAP_FAILED && q != p && p[0] == 41 && p[8192] == 43);
    CHECK(unmap_call(q, 4096) == 0);
    CHECK(unmap_call(p, 12288) == 0);
    /* The kernel may round a non-fixed hint; it never replaces the live map. */
    p = map_call(0, 4096, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    CHECK(p != MAP_FAILED && unmap_call(p, 4096) == 0);
    p = map_call(0, 4096, PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    CHECK(p != MAP_FAILED); p[0] = 7; CHECK(unmap_call(p, 4096) == 0);
    errno = 0;
    CHECK(map_call(0, 0, PROT_READ, MAP_PRIVATE | MAP_ANON, -1, 0) == MAP_FAILED && errno == EINVAL);
    errno = 0;
    CHECK(map_call(0, (size_t)-1, PROT_READ, MAP_PRIVATE | MAP_ANON, -1, 0) == MAP_FAILED && errno == ENOMEM);
    errno = 0;
    CHECK(unmap_call((void *)1, 4096) == -1 && errno == EINVAL);
    errno = 0;
    CHECK(unmap_call(0, 0) == -1 && errno == EINVAL);
    fd = open(argv[1], O_RDONLY);
    CHECK(fd >= 0);
    p = map_call(0, 4097, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    CHECK(p != MAP_FAILED && p[0] == 'A' && p[4096] == 'B');
    p[0] = 'x'; p[4096] = 'y';
    CHECK(lseek(fd, 0, SEEK_SET) == 0 && read(fd, &byte, 1) == 1 && byte == 'A');
    CHECK(lseek(fd, 4096, SEEK_SET) == 4096 && read(fd, &byte, 1) == 1 && byte == 'B');
    CHECK(close(fd) == 0 && p[0] == 'x' && unmap_call(p, 4097) == 0);
    errno = 0;
    CHECK(map_call(0, 4096, PROT_READ, MAP_PRIVATE, fd, 0) == MAP_FAILED && errno == EBADF);
    fd = open(argv[1], O_RDONLY); CHECK(fd >= 0);
    p = map_call(0, 4097, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, high);
    CHECK(p != MAP_FAILED && p[0] == 'H' && p[4096] == 'T');
    p[0] = 'z';
    CHECK(lseek(fd, high, SEEK_SET) == high && read(fd, &byte, 1) == 1 && byte == 'H');
    CHECK(unmap_call(p, 4097) == 0);
    errno = 0;
    CHECK(map_call(0, 4096, PROT_READ, MAP_PRIVATE, fd, 1) == MAP_FAILED && errno == EINVAL);
    CHECK(close(fd) == 0);
    rw = open(argv[1], O_WRONLY); CHECK(rw >= 0);
    errno = 0;
    CHECK(map_call(0, 4096, PROT_READ, MAP_PRIVATE, rw, 0) == MAP_FAILED && errno == EACCES);
    CHECK(close(rw) == 0);
#ifndef MAPPING_LIBC
    /* This bounded surface deliberately rejects unsupported bits and negatives. */
    errno = 0;
    CHECK(map_call(0, 4096, PROT_READ, MAP_PRIVATE, -1, -4096) == MAP_FAILED && errno == EINVAL);
    errno = 0;
    CHECK(map_call(0, 4096, 4, MAP_PRIVATE | MAP_ANON, -1, 0) == MAP_FAILED && errno == EINVAL);
    errno = 0;
    CHECK(map_call(0, 4096, PROT_READ, MAP_PRIVATE | 16 | MAP_ANON, -1, 0) == MAP_FAILED && errno == EINVAL);
#endif
    puts("mapping real-kernel contracts passed");
    return 0;
}
