/* Original seed-forth isolated syscall double; never a production provider. */
#include <sys/stat.h>
#include <errno.h>
#include <seed-syscall.h>
static long answer;
static long expected_number;
static long expected_first;
static long expected_second;
static int mismatch;

long __seed_syscall6(long number, long a1, long a2, long a3,
                     long a4, long a5, long a6)
{
    if (number != expected_number || a1 != expected_first ||
        a2 != expected_second || a3 || a4 || a5 || a6) mismatch = 1;
    return answer;
}

int main(void)
{
    struct stat status;
    char path[2];
    path[0] = 'x'; path[1] = 0;
    expected_number = 4;
    expected_first = (long)path;
    expected_second = (long)&status;
    errno = 1234;
    answer = 0;
    if (stat(path, &status) || errno != 1234) return 1;
    answer = -1;
    if (stat(path, &status) != -1 || errno != 1) return 2;
    answer = -4095;
    if (stat(path, &status) != -1 || errno != 4095) return 3;
    errno = 1234;
    answer = -4096;
    if (stat(path, &status) != -4096 || errno != 1234) return 4;
    expected_number = 5;
    expected_first = -7;
    answer = -EOVERFLOW;
    if (fstat(-7, &status) != -1 || errno != EOVERFLOW) return 5;
    errno = 1234;
    answer = 0;
    if (fstat(-7, &status) || errno != 1234) return 6;
    return mismatch ? 7 : 0;
}
