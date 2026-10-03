#include <ctype.h>
#include <stdio.h>
int main(void)
{
    int c;
    int side = 'A';
    if (!isalpha(side++) || side != 'B') return 1;
    for (c = -1; c <= 255; c++)
        printf("%d %d %d %d %d %d %d %d\n", c,
               !!isalpha(c), !!isalnum(c), !!isdigit(c), !!isprint(c),
               !!isspace(c), !!isupper(c), tolower(c));
    return ferror(stdout) ? 1 : 0;
}
