#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>
extern int tested_mkstemp(char *);
static int scenario;
static int entropy_calls;
static int open_calls;
static int bad_call;
static long partial_base;
long tested_temp_syscall(long n, long a, long b, long c, long d, long e, long f)
{
    long i;
    long written;
    if (e || f) bad_call = 1;
    if (n == 318) {
        entropy_calls++;
        if (c || d || b <= 0 || b > 8) bad_call = 2;
        if (scenario == 1) return -ENOSYS;
        if (scenario == 2) return 0;
        if (scenario == 0 && entropy_calls == 1) return -EINTR;
        written = b;
        if (scenario == 0 && entropy_calls == 2) {
            partial_base = a;
            if (b != 8) bad_call = 7;
            written = 3;
        }
        if (scenario == 0 && entropy_calls == 3 && (a != partial_base + 3 || b != 5)) bad_call = 8;
        for (i = 0; i < written; i++) ((unsigned char *)a)[i] = 0;
        if (scenario == 0 && entropy_calls >= 4) ((unsigned char *)a)[0] = 1;
        return written;
    }
    if (n == 2) {
        open_calls++;
        if (b != (O_RDWR | O_CREAT | O_EXCL) || c != 0600 || d) bad_call = 3;
        if (scenario == 0) {
            if (open_calls == 1) return -EINTR;
            if (open_calls == 2) return -EEXIST;
            if (strcmp((char *)a, "case.baaaaa")) bad_call = 4;
            return 17;
        }
        if (scenario == 3) return -EACCES;
        if (scenario == 4) return -EEXIST;
    }
    bad_call = 5;
    return -EIO;
}
int main(void)
{
    char name[32];
    int result;
    for (scenario = 0; scenario <= 4; scenario++) {
        entropy_calls = 0; open_calls = 0; bad_call = 0;
        strcpy(name, "case.XXXXXX"); errno = EDOM;
        result = tested_mkstemp(name);
        if (bad_call) return 10 + bad_call;
        if (scenario == 0) {
            if (result != 17 || entropy_calls != 4 || open_calls != 3
                || strcmp(name, "case.baaaaa") || errno != EDOM) return 20;
        } else {
            if (result != -1 || strcmp(name, "case.XXXXXX")) return 21;
            if (scenario == 1 && (errno != ENOSYS || open_calls)) return 22;
            if (scenario == 2 && (errno != EIO || open_calls)) return 23;
            if (scenario == 3 && (errno != EACCES || open_calls != 1)) return 24;
            if (scenario == 4 && (errno != EEXIST || open_calls != 128 || entropy_calls != 128)) return 25;
        }
    }
    entropy_calls = 0; open_calls = 0;
    strcpy(name, "bad.XXXXX");
    if (tested_mkstemp(name) != -1 || errno != EINVAL || entropy_calls || open_calls
        || strcmp(name, "bad.XXXXX")) return 26;
    puts("tempfile fault contracts passed");
    return 0;
}
