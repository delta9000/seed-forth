/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <string.h>

char *strpbrk(const char *string, const char *accept)
{
    const unsigned char *text = (const unsigned char *)string;
    const unsigned char *set;
    while (*text != 0) {
        set = (const unsigned char *)accept;
        while (*set != 0) {
            if (*text == *set)
                return (char *)text;
            set = set + 1;
        }
        text = text + 1;
    }
    return NULL;
}
