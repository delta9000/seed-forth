/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md. */
#include <string.h>

size_t strnlen(const char *string, size_t limit)
{
    size_t length = 0;
    while (length < limit && string[length]) length++;
    return length;
}
