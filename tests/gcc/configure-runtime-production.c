/* Original seed-forth real-kernel regression fixture; see LICENSE. */
#include <sys/stat.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>

static int number(const char *text)
{
    int value = 0;
    while (*text) value = value * 10 + *text++ - '0';
    return value;
}

int main(int argc, char **argv)
{
    struct stat path;
    struct stat descriptor;
    struct stat link;
    struct stat directory;
    struct stat pipe;
    int fd;
    int pfd;
    int mode;
    FILE *stream;
    if (argc != 8) return 1;
    fd = number(argv[5]);
    pfd = number(argv[6]);
    errno = 1234;
    if (stat(argv[1], &path) || errno != 1234 || !S_ISREG(path.st_mode)) return 2;
    if (fstat(fd, &descriptor) || errno != 1234) return 3;
    if (path.st_dev != descriptor.st_dev || path.st_ino != descriptor.st_ino ||
        path.st_size != descriptor.st_size || path.st_mode != descriptor.st_mode ||
        path.st_uid != descriptor.st_uid || path.st_gid != descriptor.st_gid ||
        path.st_mtime != descriptor.st_mtime ||
        path.st_mtime_nsec != descriptor.st_mtime_nsec) return 4;
    if (stat(argv[2], &link) || errno != 1234 || !S_ISREG(link.st_mode) ||
        path.st_dev != link.st_dev || path.st_ino != link.st_ino) return 5;
    if (stat(argv[3], &directory) || !S_ISDIR(directory.st_mode)) return 6;
    if (fstat(pfd, &pipe) || !S_ISFIFO(pipe.st_mode)) return 7;
    if (stat(argv[4], &path) != -1 || errno != ENOENT) return 8;
    if (fstat(-1, &path) != -1 || errno != EBADF) return 9;
    if (stat(argv[1], NULL) != -1 || errno != EFAULT) return 10;
    if (fstat(fd, NULL) != -1 || errno != EFAULT) return 11;
    mode = S_IFREG;
    if (!S_ISREG(mode++) || mode != S_IFREG + 1) return 12;
    if (!S_ISDIR(S_IFDIR | 0755) || !S_ISCHR(S_IFCHR) || !S_ISBLK(S_IFBLK) ||
        !S_ISFIFO(S_IFIFO) || !S_ISLNK(S_IFLNK) || !S_ISSOCK(S_IFSOCK)) return 13;
    if (S_ISDIR(S_IFREG) || S_ISREG(S_IFDIR) || S_ISLNK(S_IFREG)) return 14;
    if (EOVERFLOW != 75) return 15;
    stream = fopen(argv[7], "w");
    if (stream == NULL || fputs("written before exit\n", stream) < 0) return 16;
    if (printf("configure runtime\n") != 18 || fputs("exit diagnostic\n", stderr) < 0) return 17;
    /* Deliberately leave stream open: unbuffered writes must already persist. */
    exit(0);
    return 99;
}
