#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
extern void __seed_init_program_name(int, char **);
int main(int argc, char **argv)
{
    char *names[2];
    int i;
    printf("%s\n%d\n", __progname, argc);
    for (i = 0; i < argc; i++) printf("[%s]\n", argv[i]);
    if (argv[argc] != 0) return 1;
    errno = EDOM;
    __seed_init_program_name(0, 0);
    if (strcmp(__progname, "") || errno != EDOM) return 2;
    names[0] = 0;
    __seed_init_program_name(1, names);
    if (strcmp(__progname, "")) return 3;
    names[0] = "/tmp/some-tool";
    __seed_init_program_name(1, names);
    if (strcmp(__progname, "some-tool") || errno != EDOM) return 4;
    names[0] = "/tmp/";
    __seed_init_program_name(1, names);
    if (strcmp(__progname, "")) return 5;
    return 0;
}
