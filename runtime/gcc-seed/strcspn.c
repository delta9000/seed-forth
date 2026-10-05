/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <string.h>

size_t strcspn(const char *string, const char *reject)
{
    const unsigned char *text = (const unsigned char *)string;
    const unsigned char *set;
    size_t length = 0;
    while (text[length] != 0) {
        set = (const unsigned char *)reject;
        while (*set != 0) {
            if (text[length] == *set)
                return length;
            set = set + 1;
        }
        length = length + 1;
    }
    return length;
}
