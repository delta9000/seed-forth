#include <stdio.h>
#include <string.h>
#include <unistd.h>
/* SysV process entry: main's third argument is the kernel environment
   vector, argv + argc + 1, the same pointer the runtime stores in environ. */
int main(int argc, char **argv, char **envp)
{
    char **entry;
    int count = 0, foo = 0, bar = 0;
    if (argv[argc] != NULL) return 1;
    if (envp != argv + argc + 1) return 2;
    if (envp != environ) return 3;
    for (entry = envp; *entry != NULL; entry++) {
        if (strcmp(*entry, "FOO=bar") == 0) foo++;
        if (strcmp(*entry, "SEED_ENVP=two words") == 0) bar++;
        count++;
    }
    if (foo != 1 || bar != 1) return 4;
    printf("%d %d\n", argc, count);
    return 0;
}
