/* Original seed-forth implementation; see LICENSE. Process environment view. */
#include <stdlib.h>
#include <string.h>
#include <errno.h>
char **environ;
/* The vector putenv last built, its capacity in pointers (including the
   terminating NULL slot) and the number of entries before that NULL. It is
   used in place only while environ still points at it. */
static char **seed_environ_owned;
static size_t seed_environ_capacity;
static size_t seed_environ_count;
char *getenv(const char *name)
{
    size_t length;
    char **entry;
    if (!name || !*name || strchr(name, '=') || !environ) return NULL;
    length = strlen(name);
    for (entry = environ; *entry; entry++)
        if (!strncmp(*entry, name, length) && (*entry)[length] == '=')
            return *entry + length + 1;
    return NULL;
}

/* Make environ a runtime-owned malloc vector with room for one more entry.
   A foreign vector (startup storage or one the program assigned) is copied,
   never written or freed; its strings are shared, not duplicated. */
static int seed_environ_reserve(void)
{
    char **vector;
    size_t count = 0;
    size_t capacity;
    if (environ != seed_environ_owned || environ == NULL) {
        if (environ) while (environ[count]) count++;
        capacity = count + 16;
        vector = malloc(capacity * sizeof *vector);
        if (vector == NULL) return -1;
        if (count) memcpy(vector, environ, count * sizeof *vector);
        vector[count] = NULL;
        /* A previously owned vector is kept: the program may still hold
           and later restore it (pex-unix saves and restores environ). */
        seed_environ_owned = vector;
        seed_environ_capacity = capacity;
        seed_environ_count = count;
        environ = vector;
    }
    if (seed_environ_count + 1 >= seed_environ_capacity) {
        capacity = seed_environ_capacity * 2;
        vector = realloc(seed_environ_owned, capacity * sizeof *vector);
        if (vector == NULL) return -1;
        seed_environ_owned = vector;
        seed_environ_capacity = capacity;
        environ = vector;
    }
    return 0;
}

int putenv(char *string)
{
    const char *separator;
    size_t length;
    size_t index;
    int saved = errno;
    if (string == NULL || *string == '\0' || *string == '=') {
        errno = EINVAL;
        return -1;
    }
    separator = strchr(string, '=');
    length = separator ? (size_t)(separator - string) : strlen(string);
    if (seed_environ_reserve() != 0) return -1;   /* errno is ENOMEM */
    index = 0;
    while (index < seed_environ_count) {
        if (strncmp(environ[index], string, length) || environ[index][length] != '=') {
            index++;
        } else if (separator) {
            /* Replace the first match: the one getenv returns. */
            environ[index] = string;
            errno = saved;
            return 0;
        } else {
            /* NAME alone removes every NAME= entry, as glibc does. */
            memmove(environ + index, environ + index + 1,
                    (seed_environ_count - index) * sizeof *environ);
            seed_environ_count--;
        }
    }
    if (separator) {
        environ[seed_environ_count++] = string;
        environ[seed_environ_count] = NULL;
    }
    errno = saved;
    return 0;
}
