/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md.
   getdelim/getline over fgetc; the buffer grows by doubling. */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <errno.h>

ssize_t getdelim(char **line, size_t *capacity, int delimiter, FILE *stream)
{
    size_t used = 0, size;
    char *buffer, *grown;
    int byte;
    if (line == NULL || capacity == NULL || stream == NULL) {
        errno = EINVAL;
        return -1;
    }
    buffer = *line;
    size = buffer ? *capacity : 0;
    for (;;) {
        if (used + 2 > size) {
            size_t next = size < 120 ? 120 : size * 2;
            if (next > (size_t)SSIZE_MAX) { errno = EOVERFLOW; return -1; }
            grown = realloc(buffer, next);
            if (grown == NULL) return -1;
            buffer = grown;
            size = next;
            *line = buffer;
            *capacity = size;
        }
        byte = fgetc(stream);
        if (byte == EOF) break;
        buffer[used++] = (char)byte;
        if (byte == (unsigned char)delimiter) break;
    }
    buffer[used] = '\0';
    /* End of file or a read error with nothing read reports -1. */
    if (used == 0) return -1;
    return (ssize_t)used;
}

ssize_t getline(char **line, size_t *capacity, FILE *stream)
{
    return getdelim(line, capacity, '\n', stream);
}
