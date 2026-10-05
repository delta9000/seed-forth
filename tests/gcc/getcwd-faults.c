#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
extern char *tested_getcwd(char *, size_t);
static long answer;
static int calls;
static int wrong;
static char *expected;
static size_t capacity;
static int nonabsolute;
long directory_fake(long number, long a, long b, long c, long d, long e, long f)
{
    calls++;
    if (number != 79 || a != (long)expected || (unsigned long)b != capacity || c || d || e || f) wrong++;
    if (answer > 0) strcpy(expected, nonabsolute ? "(unreachable)/x" : "/ok");
    return answer;
}
int main(void)
{
    static char bytes[32];
    int error;
    expected = bytes;
    capacity = sizeof(bytes);
    for (error = 1; error <= 4095; error++) {
        memset(bytes, 85, sizeof(bytes));
        answer = -error;
        errno = 97;
        if (tested_getcwd(bytes, capacity) != NULL || errno != error || bytes[0] != 85) return 10;
    }
    if (calls != 4095 || wrong) return 11;
    answer = 4;
    capacity = 18446744073709551615UL;
    errno = 97;
    if (tested_getcwd(bytes, capacity) != bytes || errno != 97 || strcmp(bytes, "/ok")) return 12;
    capacity = 4294967297UL;
    if (tested_getcwd(bytes, capacity) != bytes || wrong) return 13;
    nonabsolute = 1;
    answer = 16;
    if (tested_getcwd(bytes, capacity) != NULL || errno != ENOENT) return 14;
    calls = 0;
    if (tested_getcwd(NULL, 0) != NULL || errno != EINVAL) return 15;
    if (tested_getcwd(bytes, 0) != NULL || errno != EINVAL) return 16;
    if (tested_getcwd(NULL, 10) != NULL || errno != EINVAL || calls) return 17;
    puts("cwd injected contracts passed");
    return 0;
}
