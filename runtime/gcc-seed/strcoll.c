/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md.
   Collation in the only supported (C/POSIX) locale is byte order. */
#include <string.h>

int strcoll(const char *left, const char *right)
{
    return strcmp(left, right);
}

size_t strxfrm(char *destination, const char *source, size_t count)
{
    size_t length = strlen(source);
    if (length < count) memcpy(destination, source, length + 1);
    return length;
}
