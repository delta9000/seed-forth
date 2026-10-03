/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <string.h>

void *memcpy(void *destination, const void *source, size_t count)
{
    unsigned char *out = destination;
    const unsigned char *in = source;
    size_t i;
    for (i = 0; i < count; i = i + 1)
        out[i] = in[i];
    return destination;
}

void *memmove(void *destination, const void *source, size_t count)
{
    unsigned char *out = destination;
    const unsigned char *in = source;
    size_t i;
    /* Integer address ordering is an explicit Linux AMD64 assumption. */
    if ((unsigned long)out <= (unsigned long)in) {
        for (i = 0; i < count; i = i + 1)
            out[i] = in[i];
    } else {
        i = count;
        while (i != 0) {
            i = i - 1;
            out[i] = in[i];
        }
    }
    return destination;
}

void *memset(void *destination, int value, size_t count)
{
    unsigned char *out = destination;
    size_t i;
    for (i = 0; i < count; i = i + 1)
        out[i] = (unsigned char)value;
    return destination;
}

int memcmp(const void *left, const void *right, size_t count)
{
    const unsigned char *a = left;
    const unsigned char *b = right;
    size_t i;
    for (i = 0; i < count; i = i + 1) {
        if (a[i] != b[i])
            return (int)a[i] - (int)b[i];
    }
    return 0;
}

void *memchr(const void *memory, int value, size_t count)
{
    const unsigned char *bytes = memory;
    size_t i;
    for (i = 0; i < count; i = i + 1) {
        if (bytes[i] == (unsigned char)value)
            return (void *)(bytes + i);
    }
    return NULL;
}
