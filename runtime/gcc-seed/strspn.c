/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <string.h>

size_t strspn(const char *string, const char *accept)
{
    const unsigned char *text = (const unsigned char *)string;
    const unsigned char *set;
    size_t length = 0;
    while (text[length] != 0) {
        set = (const unsigned char *)accept;
        while (*set != 0 && *set != text[length])
            set = set + 1;
        if (*set == 0)
            return length;
        length = length + 1;
    }
    return length;
}
