/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md. */
#include <string.h>

char *stpcpy(char *destination, const char *source)
{
    while ((*destination = *source++) != '\0') destination++;
    return destination;
}
