/* Original seed-forth implementation; see LICENSE. Runtime-aware C entry. */
#include <stdlib.h>
char *__progname = "";

void __seed_init_program_name(int count, char **arguments)
{
    char *cursor;
    __progname = "";
    if (count <= 0 || arguments == NULL || arguments[0] == NULL) return;
    __progname = arguments[0];
    cursor = arguments[0];
    while (*cursor) {
        if (*cursor == '/') __progname = cursor + 1;
        cursor++;
    }
}

