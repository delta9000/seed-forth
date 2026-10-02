/* Linux AMD64 kernel boundary, compiled exclusively by seed-forth. */
typedef unsigned long size_t;
typedef long ssize_t;
typedef long off_t;
void exit(int status);
ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
int open(const char *path, int flags, ...);
int close(int fd);
off_t lseek(int fd, off_t offset, int whence);
int unlink(const char *path);
int mkdir(const char *path, unsigned int mode);
int chmod(const char *path, unsigned int mode);
int access(const char *path, int mode);
int mprotect(void *address, size_t length, int protection);

struct timeval { long sec; long usec; };
long time(long *seconds);
int gettimeofday(struct timeval *tv, void *timezone);

int main(int argc, char **argv) {
    char data[9];
    int fd;
    long sparse = 4294967301L;
    long seconds;
    struct timeval tv;
    if (argc != 3) return 1;
    if (mkdir(argv[2], 0700) != 0) return 2;
    if (access(argv[2], 0) != 0) return 3;
    fd = open(argv[1], 578, 0600); /* O_RDWR | O_CREAT | O_TRUNC */
    if (fd < 0) return 4;
    if (write(fd, "012345678", 9) != 9) return 5;
    if (lseek(fd, 2, 0) != 2) return 6;
    if (read(fd, data, 4) != 4) return 7;
    if (data[0] != '2' || data[3] != '5') return 8;
    if (lseek(fd, sparse, 0) != sparse) return 9;
    if (write(fd, "x", 1) != 1) return 10;
    if (lseek(fd, 0, 1) != sparse + 1) return 11;
    if (close(fd) != 0) return 12;
    if (chmod(argv[1], 0400) != 0) return 13;
    fd = open(argv[1], 0); /* O_RDONLY, no mode stack slot */
    if (fd < 0) return 14;
    if (lseek(fd, sparse, 0) != sparse) return 15;
    if (read(fd, data, 1) != 1 || data[0] != 'x') return 16;
    if (close(fd) != 0) return 17;
    if (unlink(argv[1]) != 0) return 18;
    /* Every failure returns -1, including ENOENT and EBADF, not -errno. */
    if (open(argv[1], 0) != -1) return 19;
    if (access(argv[1], 0) != -1) return 20;
    if (unlink(argv[1]) != -1) return 21;
    if (chmod(argv[1], 0600) != -1) return 22;
    if (mkdir(argv[2], 0700) != -1) return 23;
    if (close(-1) != -1) return 24;
    if (read(-1, data, 1) != -1) return 25;
    if (write(-1, data, 1) != -1) return 26;
    if (lseek(-1, 0, 0) != -1) return 27;
    if (mprotect((void *)1, 4096, 3) != -1) return 28;
    if (time(&seconds) != seconds || seconds < 1) return 29;
    if (gettimeofday(&tv, (void *)0) != 0) return 30;
    if (tv.sec < seconds || tv.sec - seconds > 10) return 31;
    if (tv.usec < 0 || tv.usec >= 1000000) return 32;
    if (time((long *)0) < seconds) return 33;
    if (write(1, "native-runtime-ok\n", 18) != 18) return 34;
    return 0;
}
