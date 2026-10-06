/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md. */
#include <strings.h>

int strcasecmp(const char *left, const char *right)
{
    const unsigned char *a = (const unsigned char *)left;
    const unsigned char *b = (const unsigned char *)right;
    int x, y;
    for (;; a++, b++) {
        x = *a >= 'A' && *a <= 'Z' ? *a + 32 : *a;
        y = *b >= 'A' && *b <= 'Z' ? *b + 32 : *b;
        if (x != y || x == 0) return x - y;
    }
}
