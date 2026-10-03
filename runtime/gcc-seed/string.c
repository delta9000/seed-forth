/* Original seed-forth implementation; distributed under ../../LICENSE. */
#include <string.h>
#include <stdlib.h>

size_t strlen(const char *string)
{
    size_t length = 0;
    while (string[length] != 0)
        length = length + 1;
    return length;
}

int strcmp(const char *left, const char *right)
{
    const unsigned char *a = (const unsigned char *)left;
    const unsigned char *b = (const unsigned char *)right;
    while (*a != 0 && *a == *b) {
        a = a + 1;
        b = b + 1;
    }
    return (int)*a - (int)*b;
}

int strncmp(const char *left, const char *right, size_t count)
{
    const unsigned char *a = (const unsigned char *)left;
    const unsigned char *b = (const unsigned char *)right;
    size_t i;
    for (i = 0; i < count; i = i + 1) {
        if (a[i] != b[i])
            return (int)a[i] - (int)b[i];
        if (a[i] == 0)
            return 0;
    }
    return 0;
}

char *strcpy(char *destination, const char *source)
{
    size_t i = 0;
    while (source[i] != 0) {
        destination[i] = source[i];
        i = i + 1;
    }
    destination[i] = 0;
    return destination;
}

char *strncpy(char *destination, const char *source, size_t count)
{
    size_t i = 0;
    while (i < count && source[i] != 0) {
        destination[i] = source[i];
        i = i + 1;
    }
    while (i < count) {
        destination[i] = 0;
        i = i + 1;
    }
    return destination;
}

char *strcat(char *destination, const char *source)
{
    size_t end = strlen(destination);
    strcpy(destination + end, source);
    return destination;
}

char *strncat(char *destination, const char *source, size_t count)
{
    size_t end = strlen(destination);
    size_t i = 0;
    while (i < count && source[i] != 0) {
        destination[end + i] = source[i];
        i = i + 1;
    }
    destination[end + i] = 0;
    return destination;
}

char *strchr(const char *string, int value)
{
    unsigned char wanted = (unsigned char)value;
    const unsigned char *cursor = (const unsigned char *)string;
    while (1) {
        if (*cursor == wanted)
            return (char *)cursor;
        if (*cursor == 0)
            return NULL;
        cursor = cursor + 1;
    }
}

char *strrchr(const char *string, int value)
{
    unsigned char wanted = (unsigned char)value;
    const unsigned char *cursor = (const unsigned char *)string;
    char *last = NULL;
    while (1) {
        if (*cursor == wanted)
            last = (char *)cursor;
        if (*cursor == 0)
            return last;
        cursor = cursor + 1;
    }
}

char *strstr(const char *haystack, const char *needle)
{
    size_t i;
    if (*needle == 0)
        return (char *)haystack;
    while (*haystack != 0) {
        i = 0;
        while (needle[i] != 0 && haystack[i] == needle[i])
            i = i + 1;
        if (needle[i] == 0)
            return (char *)haystack;
        haystack = haystack + 1;
    }
    return NULL;
}

char *strdup(const char *string)
{
    size_t length = strlen(string);
    char *copy = malloc(length + 1);
    if (copy != NULL)
        memcpy(copy, string, length + 1);
    return copy;
}
