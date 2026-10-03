#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
extern FILE *tested_fdopen(int, const char *);
extern int tested_fclose(FILE *);
static long storage[16];
static int scenario;
static int gets;
static int sets;
static int closes;
static int allocations;
static int frees;
static int bad;
void *tested_stream_malloc(size_t n)
{
    allocations++;
    if (n > sizeof(storage)) bad = 1;
    if (scenario == 2) { errno = ENOMEM; return NULL; }
    return storage;
}
void tested_stream_free(void *p)
{
    if (p != storage) bad = 2;
    frees++;
}
long tested_stream_syscall(long n, long a, long b, long c, long d, long e, long f)
{
    if (a != 11 || d || e || f) bad = 3;
    if (n == 72 && b == F_GETFL) {
        gets++;
        if (c) bad = 4;
        if (scenario == 0) return -EBADF;
        if (scenario == 1) return O_RDONLY;
        if (scenario == 6) return 2097152;
        if (scenario == 4 && gets == 1) return -EINTR;
        return O_RDWR | (scenario == 5 ? O_APPEND : 0);
    }
    if (n == 72 && b == F_SETFL) {
        sets++;
        if (c != (O_RDWR | O_APPEND)) bad = 5;
        if (scenario == 3) return -EPERM;
        if (scenario == 4 && sets == 1) return -EINTR;
        return 0;
    }
    if (n == 3) { closes++; return 0; }
    bad = 6;
    return -EIO;
}
int main(void)
{
    FILE *stream;
    for (scenario = 0; scenario <= 6; scenario++) {
        gets = sets = closes = allocations = frees = bad = 0;
        errno = EDOM;
        stream = tested_fdopen(11, scenario == 1 ? "w" : "a");
        if (scenario == 4 || scenario == 5) {
            if (!stream || errno != EDOM || allocations != 1 || frees || closes) return 10;
            if (scenario == 4 && (gets != 2 || sets != 2)) return 11;
            if (scenario == 5 && (gets != 1 || sets)) return 12;
            if (tested_fclose(stream) || closes != 1 || frees != 1) return 13;
        } else {
            if (stream || closes) return 14;
            if (scenario == 0 && (errno != EBADF || allocations || sets)) return 15;
            if (scenario == 1 && (errno != EINVAL || allocations || sets)) return 16;
            if (scenario == 2 && (errno != ENOMEM || allocations != 1 || sets || frees)) return 17;
            if (scenario == 3 && (errno != EPERM || allocations != 1 || frees != 1 || sets != 1)) return 18;
            if (scenario == 6 && (errno != EBADF || allocations || sets)) return 19;
        }
        if (bad) return 20 + bad;
    }
    gets = sets = closes = allocations = frees = bad = 0;
    if (tested_fdopen(11, "q") || errno != EINVAL || gets || allocations || sets || closes) return 30;
    puts("fdopen fault contracts passed");
    return 0;
}
