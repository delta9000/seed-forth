/* The same public-contract program is compiled by Forth and host GCC/libc. */
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#ifdef DESCRIPTOR_IO_HOST_ORACLE
static long __seed_syscall6(long n, long a, long b, long c, long d, long e, long f)
{
    long result = syscall(n, a, b, c, d, e, f);
    return result == -1 ? -errno : result;
}
#else
#include <seed-syscall.h>
#endif

int main(int argc, char **argv)
{
    char path[512], linkpath[512], bytes[16];
    int fd, other, pair[2], temporary = 0;
    struct stat metadata;
    FILE *stream;
    off_t high = 4294967301L;
    mode_t create_mode = 0666;
    if (argc != 2) return 1;
    if (sizeof(off_t) != 8 || sizeof(ssize_t) != 8 || sizeof(mode_t) != 4
        || (off_t)-1 >= 0 || (ssize_t)-1 >= 0 || (mode_t)-1 <= 0) return 2;
    if (snprintf(path, sizeof(path), "%s/file", argv[1]) < 0
        || snprintf(linkpath, sizeof(linkpath), "%s/file-link", argv[1]) < 0) return 3;
    errno = 777;
    fd = open(path, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, create_mode);
    if (fd < 0 || errno != 777) return 4;
    if (fstat(fd, &metadata) || (metadata.st_mode & 0777) != 0640) return 5;
    if (__seed_syscall6(72, fd, 1, 0, 0, 0, 0) != 1) return 6;
    if (open(path, O_CREAT | O_EXCL | O_RDWR, 0600) != -1 || errno != EEXIST) return 7;
    if (write(fd, "abcdef", 6) != 6 || lseek(fd, 0, SEEK_SET) != 0) return 8;
    errno = 778;
    if (read(fd, bytes, 3) != 3 || errno != 778 || memcmp(bytes, "abc", 3)) return 9;
    if (lseek(fd, -2, SEEK_CUR) != 1 || lseek(fd, -2, SEEK_END) != 4) return 10;
    if (read(fd, bytes, sizeof(bytes)) != 2 || memcmp(bytes, "ef", 2)) return 11;
    errno = 779;
    if (read(fd, bytes, sizeof(bytes)) != 0 || errno != 779) return 12;
    if (read(fd, bytes, 0) != 0 || errno != 779) return 13;
    if (lseek(fd, -1, SEEK_SET) != -1 || errno != EINVAL) return 14;
    if (lseek(fd, 0, 12345) != -1 || errno != EINVAL) return 15;
    if (lseek(fd, high, SEEK_SET) != high || write(fd, "Z", 1) != 1) return 16;
    if (lseek(fd, -2, SEEK_END) != high - 1 || read(fd, bytes, 2) != 2
        || bytes[0] != 0 || bytes[1] != 'Z') return 17;
    if (fstat(fd, &metadata) || metadata.st_size != high + 1) return 18;
    errno = 780;
    if (close(fd) || errno != 780 || close(fd) != -1 || errno != EBADF) return 19;
    if (read(fd, bytes, 1) != -1 || errno != EBADF) return 20;
    if (read(fd, bytes, 0) != -1 || errno != EBADF) return 21;
    if (lseek(fd, high, SEEK_SET) != -1 || errno != EBADF) return 22;
    fd = open(path, O_WRONLY | O_TRUNC);
    if (fd < 0 || fstat(fd, &metadata) || metadata.st_size != 0) return 23;
    if (read(fd, bytes, 1) != -1 || errno != EBADF || close(fd)) return 24;
    fd = open(path, O_WRONLY | O_APPEND);
    if (fd < 0 || write(fd, "A", 1) != 1 || lseek(fd, 0, SEEK_SET) != 0
        || write(fd, "B", 1) != 1 || close(fd)) return 25;
    fd = open(path, O_RDONLY | O_NOCTTY);
    if (fd < 0 || read(fd, bytes, 8) != 2 || memcmp(bytes, "AB", 2)) return 26;
    stream = fdopen(fd, "w");
    if (stream || lseek(fd, 0, SEEK_SET) != 0 || read(fd, bytes, 1) != 1) return 27;
    if (close(fd)) return 28;
    if (open(linkpath, O_RDONLY | O_NOFOLLOW) != -1 || errno != 40) return 29;
    if (open(path, O_RDONLY | O_DIRECTORY) != -1 || errno != ENOTDIR) return 30;
    other = open(path, O_PATH);
    if (other < 0 || read(other, bytes, 1) != -1 || errno != EBADF || close(other)) return 31;
#ifndef DESCRIPTOR_IO_HOST_ORACLE
    /* Deliberate bounded-policy differences: Linux silently ignores some bits. */
    if (open(path, 0x40000000) != -1 || errno != EINVAL) return 32;
    if (open(path, O_ACCMODE) != -1 || errno != EINVAL) return 33;
    if (open(argv[1], 4194304 | O_RDWR) != -1 || errno != EINVAL) return 34;
    if (open(path, O_CREAT | 0x40000000) != -1 || errno != EINVAL) return 35;
#endif
    fd = open(argv[1], O_TMPFILE | O_RDWR, (mode_t)0604);
    if (fd >= 0) {
        temporary = 1;
        if (fstat(fd, &metadata) || (metadata.st_mode & 0777) != 0600
            || write(fd, "T", 1) != 1 || lseek(fd, 0, SEEK_SET)
            || read(fd, bytes, 1) != 1 || bytes[0] != 'T' || close(fd)) return 36;
    } else if (errno != 95 && errno != EISDIR && errno != ENOENT) return 37;
    if (__seed_syscall6(22, (long)pair, 0, 0, 0, 0, 0)) return 38;
    if (write(pair[1], "xyz", 3) != 3 || read(pair[0], bytes, 8) != 3
        || memcmp(bytes, "xyz", 3)) return 39;
    if (lseek(pair[0], 0, SEEK_CUR) != -1 || errno != ESPIPE) return 40;
    if (__seed_syscall6(72, pair[0], F_SETFL, O_NONBLOCK, 0, 0, 0)) return 41;
    if (read(pair[0], bytes, 8) != -1 || errno != EAGAIN) return 42;
    errno = 781;
    if (close(pair[1]) || read(pair[0], bytes, 8) || errno != 781 || close(pair[0])) return 43;
    if (close(STDIN_FILENO)) return 44;
    fd = open(path, O_RDONLY);
    if (fd != STDIN_FILENO) return 45;
    stream = fdopen(fd, "r");
    if (!stream || fileno(stream) != 0 || fgetc(stream) != 'A' || fclose(stream)) return 46;
    if (close(fd) != -1 || errno != EBADF) return 47;
    if (unlink(path)) return 48;
    if (open(path, O_RDONLY) != -1 || errno != ENOENT) return 49;
    printf("descriptor I/O contracts passed; tmpfile=%d\n", temporary);
    return 0;
}
