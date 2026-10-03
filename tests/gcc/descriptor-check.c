#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <paths.h>
#include <unistd.h>
#include <sys/stat.h>
#ifdef DESCRIPTOR_HOST_ORACLE
static long __seed_syscall6(long n,long a,long b,long c,long d,long e,long f)
{
    long r = syscall(n,a,b,c,d,e,f);
    return r == -1 ? -errno : r;
}
#else
#include <seed-syscall.h>
#endif
static int raw_open(const char *path, int flags)
{
    return (int)__seed_syscall6(2, (long)path, flags, 0600, 0, 0, 0);
}
static int raw_close(int fd) { return (int)__seed_syscall6(3, fd, 0, 0, 0, 0, 0); }
static long raw_flags(int fd) { return __seed_syscall6(72, fd, F_GETFL, 0, 0, 0, 0); }
int main(int argc, char **argv)
{
    char path[1024];
    char bytes[16];
    char bad[] = "bad.XXXXX";
    char *names[32];
    FILE *stream;
    struct stat st;
    int fd;
    int i;
    int j;
    if (argc < 2) return 1;
    if (argc > 2) {
        snprintf(path, sizeof(path), "%s/before-exit", argv[1]);
        stream = fopen(path, "w");
        if (!stream || fputs("before _exit\n", stream) == EOF) return 2;
        _exit(259);
    }
    if (strcmp(_PATH_TMP, "/tmp/")) return 3;
    errno = 0;
    if (mkstemp(bad) != -1 || errno != EINVAL || strcmp(bad, "bad.XXXXX")) return 4;
    snprintf(path, sizeof(path), "%s/main.XXXXXX", argv[1]);
    fd = mkstemp(path);
    if (fd < 0 || fstat(fd, &st) || (st.st_mode & 0777) != 0600) return 5;
    if (__seed_syscall6(1, fd, (long)"abcdef", 6, 0, 0, 0) != 6) return 6;
    if (__seed_syscall6(8, fd, 2, 0, 0, 0, 0) != 2) return 7;
    errno = EDOM;
    stream = fdopen(fd, "wb");
    if (!stream || errno != EDOM || ftell(stream) != 2) return 8;
    if (fputs("XY", stream) == EOF || fclose(stream) || raw_flags(fd) != -EBADF) return 9;
    stream = fopen(path, "r");
    if (!stream || fread(bytes, 1, 8, stream) != 6 || memcmp(bytes, "abXYef", 6) || fclose(stream)) return 10;
    fd = raw_open(path, O_RDONLY);
    errno = 0;
    if (fdopen(fd, "w") != NULL || errno != EINVAL || raw_flags(fd) < 0) return 11;
    stream = fdopen(fd, "rb");
    if (!stream || fputc('x', stream) != EOF || errno != EBADF || !ferror(stream)) return 12;
    clearerr(stream);
    if (fread(bytes, 1, 6, stream) != 6 || memcmp(bytes, "abXYef", 6) || fclose(stream)) return 13;
    fd = raw_open(path, O_WRONLY);
    if (fdopen(fd, "r+") != NULL || errno != EINVAL || raw_flags(fd) < 0) return 14;
#ifndef DESCRIPTOR_HOST_ORACLE
    if (fdopen(fd, "wbb") != NULL || errno != EINVAL || raw_flags(fd) < 0) return 15;
#endif
    stream = fdopen(fd, "a");
    if (!stream || !(raw_flags(fd) & O_APPEND)) return 16;
    if (__seed_syscall6(8, fd, 0, 0, 0, 0, 0) != 0) return 17;
    if (fputs("!", stream) == EOF || ftell(stream) != 7 || fclose(stream)) return 18;
    fd = raw_open(path, O_RDWR);
    stream = fdopen(fd, "w+b");
    if (!stream || fread(bytes, 1, 7, stream) != 7 || memcmp(bytes, "abXYef!", 7) || fclose(stream)) return 19;
    if (fdopen(-1, "r") != NULL || errno != EBADF) return 20;
#ifndef DESCRIPTOR_HOST_ORACLE
    fd = raw_open(path, 2097152); /* Linux O_PATH is not a readable stream. */
    if (fd < 0 || fdopen(fd, "r") != NULL || errno != EBADF || raw_flags(fd) < 0 || raw_close(fd)) return 21;
#endif
    errno = EDOM;
    if (unlink(path) || errno != EDOM) return 22;
    if (unlink(path) != -1 || errno != ENOENT) return 23;
    for (i = 0; i < 32; i++) {
        names[i] = malloc(1024);
        if (!names[i]) return 24;
        snprintf(names[i], 1024, "%s/multiple.XXXXXXXXXX", argv[1]);
        fd = mkstemp(names[i]);
        if (fd < 0 || fstat(fd, &st) || (st.st_mode & 0777) != 0600
            || (raw_flags(fd) & O_ACCMODE) != O_RDWR) return 25;
        for (j = 0; j < i; j++) if (!strcmp(names[j], names[i])) return 26;
        if (raw_close(fd)) return 27;
    }
    for (i = 0; i < 32; i++) {
        if (unlink(names[i])) return 28;
        free(names[i]);
    }
    snprintf(path, sizeof(path), "%s/unlinked.XXXXXX", argv[1]);
    fd = mkstemp(path);
    if (fd < 0 || unlink(path) || fstat(fd, &st) || st.st_nlink != 0) return 29;
    stream = fdopen(fd, "w");
    if (!stream || fputs("still open", stream) == EOF || fclose(stream)) return 30;
    snprintf(path, sizeof(path), "%s/missing/failed.XXXXXX", argv[1]);
    if (mkstemp(path) != -1 || errno != ENOENT) return 31;
#ifndef DESCRIPTOR_HOST_ORACLE
    if (strcmp(path + strlen(path) - 6, "XXXXXX")) return 32;
#endif
    puts("descriptor contracts passed");
    return 0;
}
