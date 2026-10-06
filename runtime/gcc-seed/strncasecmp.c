/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md. */
#include <strings.h>

int strncasecmp(const char *left, const char *right, size_t count)
{
    const unsigned char *a = (const unsigned char *)left;
    const unsigned char *b = (const unsigned char *)right;
    int x, y;
    for (; count; count--, a++, b++) {
        x = *a >= 'A' && *a <= 'Z' ? *a + 32 : *a;
        y = *b >= 'A' && *b <= 'Z' ? *b + 32 : *b;
        if (x != y || x == 0) return x - y;
    }
    return 0;
}
