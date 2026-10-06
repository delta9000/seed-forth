/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md. */
#include <ctype.h>

int isblank(int value)
{
    return value == ' ' || value == '\t';
}
