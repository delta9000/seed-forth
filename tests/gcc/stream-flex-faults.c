/* Scripted syscall faults, compiled by Forth only for this test executable. */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <seed-syscall.h>
static int scenario;
static int calls;
static int invalid;
long __seed_syscall6(long number, long a1, long a2, long a3, long a4, long a5, long a6)
{
    int step = calls++;
    if (a4 || a5 || a6) invalid = 1;
    if (scenario <= 3) {
        if (step == 0) {
            if (number != 3 || a1 != 1 || a2 || a3) invalid = 1;
            return -EINTR;
        }
        if (step == 1 || (scenario == 1 && step == 2)) {
            if (number != 2 || strcmp((char *)a1,"target") || a2 != 578 || a3 != 0666) invalid = 1;
            if (scenario == 2) return -EACCES;
            if (scenario == 1 && step == 1) return -EINTR;
            return 7;
        }
        if ((scenario == 1 && (step == 3 || step == 4)) || (scenario == 3 && step == 2)) {
            if (number != 33 || a1 != 7 || a2 != 1 || a3) invalid = 1;
            if (scenario == 3) return -EBADF;
            return step == 3 ? -EINTR : 1;
        }
        if ((scenario == 1 && step == 5) || (scenario == 3 && step == 3)) {
            if (number != 3 || a1 != 7 || a2 || a3) invalid = 1;
            return -EINTR;
        }
    } else if (scenario == 4) {
        if (number != 0 || a1 || a3 != 1) invalid = 1;
        if (step == 0) return -EINTR;
        if (step == 1 || step == 3) { *(char *)a2 = step == 1 ? 'a' : 'b'; return 1; }
        if (step == 2) return -EIO;
        if (step == 4) return 0;
    } else if (scenario == 5) {
        if (step == 0 || step == 3) {
            if (number != 0 || a1 || a3 != 1) invalid = 1;
            if (step == 3) return 0;
            *(char *)a2 = 'a'; return 1;
        }
        if (step == 1 || step == 2) {
            if (number != 8 || a1 || a2 != -1 || a3 != SEEK_CUR) invalid = 1;
            return step == 1 ? -EINTR : -ESPIPE;
        }
        if (step == 4) {
            if (number != 8 || a1 || a2 != 7 || a3 != SEEK_SET) invalid = 1;
            return 7;
        }
    }
    invalid = 1;
    return -ENOSYS;
}
int main(int argc, char **argv)
{
    char buffer[8];
    FILE *result;
    if (argc != 2) return 1;
    scenario = argv[1][0] - '0';
    if (scenario <= 3) {
        errno = EDOM;
        result = freopen("target","w+",stdout);
        if (scenario == 1) {
            if (result != stdout || fileno(stdout) != 1 || calls != 6 || errno != EDOM || feof(stdout) || ferror(stdout)) return 2;
        } else {
            if (result != NULL || errno != (scenario == 2 ? EACCES : EBADF) || calls != (scenario == 2 ? 2 : 4)) return 3;
            if (fileno(stdout) != -1 || errno != EBADF || ferror(stdout) || feof(stdout)) return 4;
        }
    } else if (scenario == 4) {
        if (fgets(buffer,sizeof(buffer),stdin) != NULL || errno != EIO || !ferror(stdin) || feof(stdin) || calls != 3) return 5;
        if (fgets(buffer,sizeof(buffer),stdin) != buffer || strcmp(buffer,"b") || !ferror(stdin) || !feof(stdin) || calls != 5) return 6;
    } else if (scenario == 5) {
        if (fgetc(stdin) != 'a' || ungetc('Q',stdin) != 'Q' || calls != 1) return 7;
        if (fseek(stdin,LONG_MIN,SEEK_CUR) != -1 || errno != EOVERFLOW || calls != 1) return 8;
        if (fseek(stdin,0,SEEK_CUR) != -1 || errno != ESPIPE || calls != 3 || getc(stdin) != 'Q' || calls != 3) return 9;
        if (getc(stdin) != EOF || !feof(stdin) || ferror(stdin) || calls != 4) return 10;
        if (fseek(stdin,7,SEEK_SET) || feof(stdin) || ferror(stdin) || calls != 5) return 11;
    } else if (scenario == 6) {
        if (fgets(buffer,1,stdin) != buffer || buffer[0] || calls) return 12;
        if (fgets(buffer,0,stdin) != NULL || errno != EINVAL || calls) return 13;
        if (fgets(buffer,sizeof(buffer),stdout) != NULL || errno != EBADF || !ferror(stdout) || calls) return 14;
    } else return 15;
    return invalid ? 16 : 0;
}
