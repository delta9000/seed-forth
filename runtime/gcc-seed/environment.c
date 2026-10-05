/* Original seed-forth implementation; see LICENSE. Process environment view. */
#include <stdlib.h>
#include <string.h>
char **environ;
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
