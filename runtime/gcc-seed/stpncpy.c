/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md. */
#include <string.h>

char *stpncpy(char *destination, const char *source, size_t count)
{
    /* Copy at most COUNT bytes and pad with NULs; return a pointer to the
       first NUL written, or to DESTINATION + COUNT when none was. */
    size_t length = strnlen(source, count);
    memcpy(destination, source, length);
    memset(destination + length, 0, count - length);
    return destination + length;
}
