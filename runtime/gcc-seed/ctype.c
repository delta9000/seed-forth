/* Original seed-forth implementation; see LICENSE. Fixed ASCII C locale. */
#include <ctype.h>
int isupper(int value) { return value >= 'A' && value <= 'Z'; }
int islower(int value) { return value >= 'a' && value <= 'z'; }
int isascii(int value) { return value >= 0 && value <= 127; }
int isalpha(int value)
{
    return isupper(value) || (value >= 'a' && value <= 'z');
}
int isdigit(int value) { return value >= '0' && value <= '9'; }
int isalnum(int value) { return isalpha(value) || isdigit(value); }
int isprint(int value) { return value >= 32 && value <= 126; }
int iscntrl(int value) { return (value >= 0 && value < 32) || value == 127; }
int isgraph(int value) { return value >= 33 && value <= 126; }
int ispunct(int value) { return isgraph(value) && !isalnum(value); }
int isspace(int value)
{
    return value == ' ' || (value >= '\t' && value <= '\r');
}
int tolower(int value) { return isupper(value) ? value + ('a' - 'A') : value; }
int toupper(int value) { return islower(value) ? value - ('a' - 'A') : value; }
int isxdigit(int value)
{
    return isdigit(value) || (value >= 'a' && value <= 'f')
        || (value >= 'A' && value <= 'F');
}
