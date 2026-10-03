/* Original seed-forth fixture: exit must not return or lose status bits. */
#include <stdlib.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    int status = 0;
    int negative = 0;
    char *text;
    if (argc != 2) return 98;
    text = argv[1];
    if (*text == '-') { negative = 1; text++; }
    while (*text) status = status * 10 + *text++ - '0';
    if (negative) status = -status;
    if (fputs("before exit\n", stdout) < 0) return 97;
    exit(status);
    fputs("exit returned\n", stdout);
    return 99;
}
