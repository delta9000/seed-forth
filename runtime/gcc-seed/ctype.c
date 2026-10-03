/* Original seed-forth implementation; see LICENSE. Fixed ASCII C locale. */
#include <ctype.h>
int isupper(int value) { return value >= 'A' && value <= 'Z'; }
int isalpha(int value)
{
    return isupper(value) || (value >= 'a' && value <= 'z');
}
int isdigit(int value) { return value >= '0' && value <= '9'; }
int isalnum(int value) { return isalpha(value) || isdigit(value); }
int isprint(int value) { return value >= 32 && value <= 126; }
int isspace(int value)
{
    return value == ' ' || (value >= '\t' && value <= '\r');
}
int tolower(int value) { return isupper(value) ? value + ('a' - 'A') : value; }
