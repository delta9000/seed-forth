/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md.
   BSD names for string and memory operations. */
#include <strings.h>
#include <string.h>

char *index(const char *string, int value) { return strchr(string, value); }
char *rindex(const char *string, int value) { return strrchr(string, value); }
void bzero(void *destination, size_t count) { memset(destination, 0, count); }
void bcopy(const void *source, void *destination, size_t count)
{
    memmove(destination, source, count);
}
int bcmp(const void *left, const void *right, size_t count)
{
    return memcmp(left, right, count) != 0;
}
int ffs(int value)
{
    unsigned int bits = (unsigned int)value;
    int position = 1;
    if (bits == 0) return 0;
    while (!(bits & 1U)) {
        bits >>= 1;
        position++;
    }
    return position;
}
