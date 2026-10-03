#include <unistd.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv)
{
    const char *options = "b:dlo:p:rtv";
    int option;
    int round;
    if (argc > 1 && strcmp(argv[1], "colon") == 0) {
        options = ":b:dlo:p:rtv";
        argv++;argc--;
    } else if (argc > 1 && strcmp(argv[1], "diagnostic") == 0) {
        argv++;argc--;
    } else opterr = 0;
    argv[0] = "oyacc-test";
    for (round = 0; round < 2; round++) {
        while ((option = getopt(argc, argv, options)) != -1) {
            printf("%d %d %s\n", option, optind, optarg ? optarg : "(null)");
            if (option == '?' || option == ':') printf("optopt %d\n", optopt);
        }
        if (optarg != 0) return 5;
        printf("end %d", optind);
        while (optind < argc) printf(" %s", argv[optind++]);
        putchar('\n');
        /* POSIX restart after completed parsing, at an argument boundary. */
        optind = 1;
    }
    return ferror(stdout) ? 1 : 0;
}
