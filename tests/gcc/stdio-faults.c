/* Scripted syscall faults: Forth-built test double, never a production shim. */
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <seed-syscall.h>
static int calls;
static int scenario;
static char captured[64];
static int captured_count;

long __seed_syscall6(long number, long a1, long a2, long a3, long a4, long a5, long a6)
{
    long amount;
    char *data;
    if (number == 3) { calls = calls + 1; return -EINTR; }
    if (number != 0 && number != 1) return -ENOSYS;
    calls = calls + 1;
    data = (char *)a2;
    if (calls == 1) return -EINTR;
    if (scenario == 1 && calls >= 3) return -ENOSPC;
    if (scenario == 4 && calls >= 4) return -ENOSPC;
    if (scenario == 2) return 0;
    if (scenario == 3 && calls >= 3) return -EAGAIN;
    if (number == 0) {
        if (calls >= 4) return 0;
        data[0] = 'a' + calls - 2;
        return 1;
    }
    amount = a3 < 2 ? a3 : 2;
    memcpy(captured + captured_count, data, amount);
    captured_count = captured_count + (int)amount;
    return amount;
}

static void reset(int next)
{
    scenario = next;
    calls = 0;
    captured_count = 0;
    memset(captured, 0, sizeof(captured));
    clearerr(stdout);
    clearerr(stdin);
}

int main(void)
{
    char buffer[8];
    reset(0);
    if (fwrite("abcde", 1, 5, stdout) != 5 || calls != 4 || memcmp(captured, "abcde", 5)) return 1;
    if (ferror(stdout)) return 2;
    reset(1);
    if (fwrite("abcdef", 3, 2, stdout) != 0 || calls != 3 || captured_count != 2 || errno != ENOSPC || !ferror(stdout)) return 3;
    reset(2);
    if (fputs("x", stdout) != EOF || errno != EIO || !ferror(stdout) || calls != 2) return 4;
    reset(3);
    if (fprintf(stdout, "abcdef") != -1 || errno != EAGAIN || !ferror(stdout) || captured_count != 2) return 5;
    reset(0);
    if (fread(buffer, 1, 5, stdin) != 2 || memcmp(buffer, "ab", 2) || !feof(stdin) || ferror(stdin) || calls != 4) return 6;
    if (getc(stdin) != EOF || calls != 4) return 7;
    if (ungetc('Z', stdin) != 'Z' || feof(stdin) || getc(stdin) != 'Z' || calls != 4) return 8;
    reset(3);
    if (fread(buffer, 2, 2, stdin) != 0 || buffer[0] != 'a' || errno != EAGAIN || !ferror(stdin) || feof(stdin)) return 9;
    reset(0);
    if (fwrite("", 0, 100, stdout) || fread(buffer, 100, 0, stdin) || calls) return 10;
    if (fwrite("x", (size_t)-1, 2, stdout) || errno != 75 || calls || !ferror(stdout)) return 11;
    reset(4);
    if (fwrite("abcdef", 3, 2, stdout) != 1 || calls != 4 || captured_count != 4 || !ferror(stdout)) return 14;
    reset(0);
    if (fclose(stdout) != EOF || errno != EINTR || calls != 1) return 12;
    if (fputc('x', stdout) != EOF || errno != EBADF || calls != 1) return 13;
    return 0;
}
