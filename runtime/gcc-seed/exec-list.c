/* Original seed-forth implementation; see LICENSE and PROCESS-POSIX.md.
   execl, execlp and execle: collect the NULL-terminated argument list. */
#include <unistd.h>
#include <stdarg.h>
#include <errno.h>

#define SEED_EXEC_ARGUMENTS 4096

/* Fill VECTOR from FIRST and the variadic list; returns the count or -1
   (E2BIG) when the list does not fit, leaving LIST after the NULL. */
static int seed_exec_collect(char **vector, const char *first, va_list *list)
{
    int count = 0;
    char *next = (char *)first;
    for (;;) {
        if (count == SEED_EXEC_ARGUMENTS) {
            errno = E2BIG;
            return -1;
        }
        vector[count++] = next;
        if (next == NULL) return count;
        next = va_arg(*list, char *);
    }
}

int execl(const char *path, const char *argument, ...)
{
    char *vector[SEED_EXEC_ARGUMENTS];
    va_list list;
    int count;
    va_start(list, argument);
    count = seed_exec_collect(vector, argument, &list);
    va_end(list);
    if (count < 0) return -1;
    return execve(path, vector, environ);
}

int execlp(const char *file, const char *argument, ...)
{
    char *vector[SEED_EXEC_ARGUMENTS];
    va_list list;
    int count;
    va_start(list, argument);
    count = seed_exec_collect(vector, argument, &list);
    va_end(list);
    if (count < 0) return -1;
    return execvp(file, vector);
}

int execle(const char *path, const char *argument, ...)
{
    char *vector[SEED_EXEC_ARGUMENTS];
    char **environment;
    va_list list;
    int count;
    va_start(list, argument);
    count = seed_exec_collect(vector, argument, &list);
    /* The environment pointer follows the terminating NULL. */
    environment = count < 0 ? NULL : va_arg(list, char **);
    va_end(list);
    if (count < 0) return -1;
    return execve(path, vector, environment);
}
