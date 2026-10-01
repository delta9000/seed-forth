/* runargs FILE PROG [ARG...]: execve PROG with ARG... and then one more
 * argument per line of FILE.  The recipe runner passes at most 127
 * arguments per line; runargs carries the long lists (musl's 1,261-object
 * archive).  No shell, globbing or quoting: each line is one argument.
 *
 * Built by tcc-boot2 against portable_libc, whose execvp is a stub, so the
 * execve system call is made directly.
 */
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#define MAXARG 8192

long sys3(long n, long a, long b, long c) {
    long r;
    __asm__ volatile ("syscall" : "=a"(r) : "a"(n), "D"(a), "S"(b), "d"(c)
                      : "rcx", "r11", "memory");
    return r;
}

void fail(char *msg) {
    fprintf(stderr, "runargs: %s\n", msg);
    exit(125);
}

int main(int argc, char **argv) {
    char **v;
    char *buf;
    int fd;
    int size;
    int n;
    int i;
    int k;
    if (argc < 3) fail("usage: runargs FILE PROG [ARG...]");
    fd = open(argv[1], 0, 0);
    if (fd < 0) fail(argv[1]);
    buf = malloc(1 << 20);
    size = 0;
    while ((n = read(fd, buf + size, (1 << 20) - 1 - size)) > 0)
        size = size + n;
    if (n < 0) fail("read");
    if (size == (1 << 20) - 1) fail("argument file too large");
    close(fd);
    buf[size] = 0;
    v = malloc(MAXARG * sizeof(char *));
    k = 0;
    for (i = 2; i < argc; i = i + 1)
        v[k++] = argv[i];
    i = 0;
    while (i < size) {
        if (k >= MAXARG - 1) fail("too many arguments");
        v[k++] = buf + i;
        while (i < size && buf[i] != '\n') i = i + 1;
        if (i == size) fail("argument file must end in a newline");
        buf[i] = 0;
        i = i + 1;
    }
    v[k] = 0;
    sys3(59, (long)v[0], (long)v, 0);
    fail("execve failed");
    return 125;
}
