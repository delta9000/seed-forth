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


/* Only the runtime entry passes a complete kernel argv/environment vector. */
extern char **environ;
void __seed_init_runtime(int count, char **arguments)
{
    __seed_init_program_name(count, arguments);
    environ = count >= 0 && arguments != NULL ? arguments + count + 1 : NULL;
}
