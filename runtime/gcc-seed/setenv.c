/* Original seed-forth implementation; see LICENSE and ENVIRONMENT.md.
   setenv copies NAME=VALUE into new storage and installs it with putenv;
   replaced strings are not freed (callers may still hold getenv results). */
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static int seed_environment_name(const char *name)
{
    if (name == NULL || *name == '\0' || strchr(name, '=') != NULL) {
        errno = EINVAL;
        return 0;
    }
    return 1;
}

int setenv(const char *name, const char *value, int overwrite)
{
    size_t name_length, value_length;
    char *entry;
    if (!seed_environment_name(name)) return -1;
    if (!overwrite && getenv(name) != NULL) return 0;
    if (value == NULL) value = "";
    name_length = strlen(name);
    value_length = strlen(value);
    entry = malloc(name_length + value_length + 2);
    if (entry == NULL) return -1;
    memcpy(entry, name, name_length);
    entry[name_length] = '=';
    memcpy(entry + name_length + 1, value, value_length + 1);
    if (putenv(entry) != 0) {
        free(entry);
        return -1;
    }
    return 0;
}

int unsetenv(const char *name)
{
    if (!seed_environment_name(name)) return -1;
    /* putenv of a bare NAME removes every NAME= entry. */
    return putenv((char *)name);
}
