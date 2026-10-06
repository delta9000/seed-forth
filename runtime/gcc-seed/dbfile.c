/* Original seed-forth implementation; see LICENSE and PASSWD.md.
   Reading the colon-separated user and group databases. */
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <seed-dbfile.h>

char *__seed_load_file(const char *path)
{
    char *text = NULL, *grown;
    size_t used = 0, capacity = 0;
    ssize_t count;
    int descriptor, saved;
    descriptor = open(path, O_RDONLY | O_CLOEXEC);
    if (descriptor < 0) return NULL;
    for (;;) {
        if (capacity - used < 4097) {
            grown = realloc(text, capacity + 16384);
            if (grown == NULL) {
                saved = errno;
                free(text);
                close(descriptor);
                errno = saved;
                return NULL;
            }
            text = grown;
            capacity += 16384;
        }
        count = read(descriptor, text + used, 4096);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) {
            saved = errno;
            free(text);
            close(descriptor);
            errno = saved;
            return NULL;
        }
        if (count == 0) break;
        used += (size_t)count;
    }
    close(descriptor);
    text[used] = '\0';
    return text;
}

char *__seed_next_entry(char **cursor)
{
    char *line, *end;
    while (**cursor) {
        line = *cursor;
        end = strchr(line, '\n');
        if (end) {
            *end = '\0';
            *cursor = end + 1;
        } else {
            *cursor = line + strlen(line);
        }
        /* As glibc's files database: leading blanks are ignored. */
        while (*line == ' ' || *line == '\t') line++;
        if (*line && *line != '#' && *line != '+') return line;
    }
    return NULL;
}

int __seed_split_fields(char *line, char **fields, int count)
{
    int index = 0, colons = 0;
    char *cursor, *colon;
    /* Count first: a short line is left unmodified for another attempt. */
    for (cursor = line; *cursor; cursor++)
        if (*cursor == ':') colons++;
    if (colons < count - 1) return 0;
    fields[index++] = line;
    while (index < count) {
        colon = strchr(fields[index - 1], ':');
        *colon = '\0';
        fields[index++] = colon + 1;
    }
    return 1;
}

int __seed_parse_id(const char *text, unsigned int *value)
{
    unsigned long result = 0;
    int digits = 0;
    while (*text >= '0' && *text <= '9') {
        result = result * 10 + (unsigned long)(*text - '0');
        if (++digits > 10 || result > 4294967295UL) return 0;
        text++;
    }
    if (digits == 0 || *text != '\0') return 0;
    *value = (unsigned int)result;
    return 1;
}
