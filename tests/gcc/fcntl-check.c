/* The same public fcntl contract program is compiled by Forth and host GCC/libc.
   Process creation is test scaffolding: raw Linux fork/execve/wait4 here,
   libc under FCNTL_HOST_ORACLE, independent of the runtime process API. */
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#ifdef FCNTL_HOST_ORACLE
#include <sys/wait.h>
static int make_pipe(int pair[2]) { return pipe(pair); }
static long spawn_status(char **arguments)
{
    int status;
    pid_t child = fork();
    if (child == 0) { execve(arguments[0], arguments, environ); _exit(127); }
    if (child < 0 || waitpid(child, &status, 0) != child) return -1;
    return status;
}
#else
#include <seed-syscall.h>
static int make_pipe(int pair[2])
{
    long result = __seed_syscall6(22, (long)pair, 0, 0, 0, 0, 0);
    return result ? -1 : 0;
}
static long spawn_status(char **arguments)
{
    int status = 0;
    long child = __seed_syscall6(57, 0, 0, 0, 0, 0, 0);
    if (child == 0) {
        __seed_syscall6(59, (long)arguments[0], (long)arguments, (long)environ, 0, 0, 0);
        _exit(127);
    }
    if (child < 0 || __seed_syscall6(61, child, (long)&status, 0, 0, 0, 0) != child) return -1;
    return status;
}
#endif

/* Exit status of a child shell that writes to descriptor 9 (0 when open). */
static long probe_descriptor_nine(void)
{
    static char shell[] = "/bin/sh", name[] = "sh", option[] = "-c";
    static char script[] = "exec 2>/dev/null; echo x >&9";
    char *arguments[5];
    arguments[0] = shell; arguments[1] = option; arguments[2] = script;
    arguments[3] = name; arguments[4] = 0;
    return spawn_status(arguments);
}

int main(int argc, char **argv)
{
    char path[512], byte;
    int pair[2], fd, copy, other, flags;
    if (argc != 2) return 1;
    if (F_DUPFD != 0 || F_GETFD != 1 || F_SETFD != 2 || F_GETFL != 3
        || F_SETFL != 4 || F_DUPFD_CLOEXEC != 1030 || FD_CLOEXEC != 1) return 2;
    if (make_pipe(pair)) return 3;
    /* Descriptor flags: two-argument form, explicit argument, NULL argument. */
    errno = 701;
    if (fcntl(pair[0], F_GETFD) != 0 || errno != 701) return 4;
    if (fcntl(pair[0], F_SETFD, FD_CLOEXEC) != 0 || errno != 701) return 5;
    if (fcntl(pair[0], F_GETFD, 0) != FD_CLOEXEC) return 6;
    if (fcntl(pair[1], F_GETFD) != 0) return 7;
    if (fcntl(pair[0], F_SETFD, 0) != 0 || fcntl(pair[0], F_GETFD) != 0) return 8;
    /* Status flags: access mode and O_NONBLOCK round trip with real EAGAIN. */
    flags = fcntl(pair[0], F_GETFL, NULL);
    if (flags < 0 || (flags & O_ACCMODE) != O_RDONLY || (flags & O_NONBLOCK)) return 9;
    if ((fcntl(pair[1], F_GETFL) & O_ACCMODE) != O_WRONLY) return 10;
    if (fcntl(pair[0], F_SETFL, flags | O_NONBLOCK) != 0) return 11;
    if (!(fcntl(pair[0], F_GETFL) & O_NONBLOCK)) return 12;
    if (read(pair[0], &byte, 1) != -1 || errno != EAGAIN) return 13;
    if (fcntl(pair[0], F_SETFL, flags) != 0 || (fcntl(pair[0], F_GETFL) & O_NONBLOCK)) return 14;
    /* F_SETFL leaves the access mode alone. */
    if (fcntl(pair[1], F_SETFL, O_RDWR) != 0 || (fcntl(pair[1], F_GETFL) & O_ACCMODE) != O_WRONLY) return 15;
    /* Regular file: O_RDWR access and O_APPEND round trip. */
    if (snprintf(path, sizeof(path), "%s/file", argv[1]) < 0) return 16;
    fd = open(path, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0600);
    if (fd < 0 || unlink(path)) return 17;
    if (fcntl(fd, F_GETFD) != FD_CLOEXEC) return 18;
    flags = fcntl(fd, F_GETFL);
    if ((flags & O_ACCMODE) != O_RDWR || (flags & O_APPEND)) return 19;
    if (fcntl(fd, F_SETFL, flags | O_APPEND) || !(fcntl(fd, F_GETFL) & O_APPEND)) return 20;
    if (write(fd, "ab", 2) != 2 || lseek(fd, 0, SEEK_SET) != 0
        || write(fd, "c", 1) != 1 || lseek(fd, 0, SEEK_CUR) != 3) return 21;
    /* F_DUPFD: lowest free descriptor >= minimum, close-on-exec cleared,
       shared open file description (status flags and offset). */
    copy = fcntl(fd, F_DUPFD, 20);
    if (copy != 20 || fcntl(copy, F_GETFD) != 0) return 22;
    other = fcntl(fd, F_DUPFD, 20);
    if (other != 21 || close(other)) return 23;
    if (fcntl(copy, F_SETFL, O_NONBLOCK) || !(fcntl(fd, F_GETFL) & O_NONBLOCK)
        || (fcntl(fd, F_GETFL) & O_APPEND)) return 24;
    if (lseek(copy, 1, SEEK_SET) != 1 || lseek(fd, 0, SEEK_CUR) != 1) return 25;
    if (fcntl(fd, F_DUPFD, 0) < 3) return 26;
    if (close(fcntl(fd, F_DUPFD, 0))) return 27;
    /* F_DUPFD_CLOEXEC sets the new descriptor's flag only. */
    other = fcntl(pair[0], F_DUPFD_CLOEXEC, 30);
    if (other != 30 || fcntl(other, F_GETFD) != FD_CLOEXEC || fcntl(pair[0], F_GETFD) != 0) return 28;
    if (close(other) || close(copy) || close(fd)) return 29;
    if (fcntl(pair[0], F_DUPFD, -1) != -1 || errno != EINVAL) return 30;
    /* Invalid descriptors: kernel EBADF for every supported command. */
    errno = 0;
    if (fcntl(fd, F_GETFD) != -1 || errno != EBADF) return 31;
    errno = 0;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) != -1 || errno != EBADF) return 32;
    errno = 0;
    if (fcntl(-1, F_GETFL) != -1 || errno != EBADF) return 33;
    errno = 0;
    if (fcntl(fd, F_SETFL, O_NONBLOCK) != -1 || errno != EBADF) return 34;
    errno = 0;
    if (fcntl(fd, F_DUPFD, 0) != -1 || errno != EBADF) return 35;
    errno = 0;
    if (fcntl(fd, F_DUPFD_CLOEXEC, 0) != -1 || errno != EBADF) return 36;
    /* A command unknown to Linux too. */
    errno = 0;
    if (fcntl(pair[0], 9999, 0) != -1 || errno != EINVAL) return 37;
#ifndef FCNTL_HOST_ORACLE
    /* Real Linux commands outside the bounded runtime: EINVAL, descriptor
       untouched, even when the descriptor itself is invalid. */
    errno = 0;
    if (fcntl(pair[0], 5, (void *)0) != -1 || errno != EINVAL) return 38;
    errno = 0;
    if (fcntl(pair[0], 9) != -1 || errno != EINVAL) return 39;
    errno = 0;
    if (fcntl(pair[0], 1031, 65536) != -1 || errno != EINVAL) return 40;
    errno = 0;
    if (fcntl(-1, 1025) != -1 || errno != EINVAL) return 41;
    if (fcntl(pair[0], F_GETFD) != 0) return 42;
#endif
    /* Close-on-exec takes effect across a real execve. */
    if (fcntl(pair[1], F_DUPFD, 9) != 9) return 43;
    if (probe_descriptor_nine() != 0) return 44;
    if (fcntl(9, F_SETFD, FD_CLOEXEC) || probe_descriptor_nine() == 0) return 45;
    if (probe_descriptor_nine() < 0) return 46;
    if (fcntl(9, F_SETFD, 0) || probe_descriptor_nine() != 0) return 47;
    /* Only the two successful probes wrote to the pipe. */
    if (close(9) || close(pair[1])) return 48;
    if (read(pair[0], path, sizeof(path)) != 4 || memcmp(path, "x\nx\n", 4)) return 49;
    if (read(pair[0], path, 1) != 0 || close(pair[0])) return 50;
    printf("fcntl contracts passed\n");
    return 0;
}
