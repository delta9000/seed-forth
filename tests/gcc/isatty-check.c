/* Original seed-forth regression fixture; see LICENSE. */
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
int main(int argc, char **argv)
{
    int descriptor = 0;
    int i;
    int value;
    if (argc != 2) return 1;
    for (i = 0; argv[1][i]; i++) descriptor = descriptor * 10 + argv[1][i] - '0';
    errno = EDOM; value = isatty(descriptor);
    printf("%d %d\n",value,errno);
    errno = EDOM; value = isatty(-1);
    printf("%d %d\n",value,errno);
    return 0;
}
