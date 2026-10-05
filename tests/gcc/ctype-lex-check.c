/* Original seed-forth regression fixture; see LICENSE. */
#include <ctype.h>
#include <stdio.h>
#include <limits.h>
int main(void)
{
    int c;
    int side;
    int (*ascii_function)(int) = isascii;
    int (*lower_function)(int) = islower;
    int (*hex_function)(int) = isxdigit;
    int (*upper_function)(int) = toupper;
    side = 'a';
    if (!lower_function(side++) || side != 'b') return 1;
    side = 'f';
    if (!hex_function(side++) || side != 'g') return 2;
    side = 'a';
    if (upper_function(side++) != 'A' || side != 'b') return 3;
    if (ascii_function(INT_MIN) || ascii_function(INT_MAX) || ascii_function(256) || ascii_function(-2)) return 4;
    for (c = -1; c <= 255; c++)
        printf("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n", c,
               !!isalpha(c), !!isalnum(c), !!isdigit(c), !!isprint(c),
               !!isspace(c), !!isupper(c), tolower(c), !!isascii(c),
               !!islower(c), !!isxdigit(c), toupper(c),
               !!iscntrl(c), !!isgraph(c), !!ispunct(c));
    return ferror(stdout) ? 1 : 0;
}
