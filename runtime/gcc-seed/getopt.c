/* Original seed-forth implementation; see LICENSE. Short options only. */
#include <unistd.h>
#include <stdio.h>
#include <string.h>
char *optarg;
int optind = 1;
int opterr = 1;
int optopt;
static int seed_option_position = 1;

int getopt(int count, char *const arguments[], const char *options)
{
    int option;
    const char *spec;
    const char *program;
    optarg = NULL;
    if (optind <= 0) {
        optind = 1;
        seed_option_position = 1;
    }
    if (seed_option_position == 1) {
        if (optind >= count || arguments[optind][0] != '-'
            || arguments[optind][1] == '\0') return -1;
        if (strcmp(arguments[optind], "--") == 0) {
            optind++;
            return -1;
        }
    }
    option = (unsigned char)arguments[optind][seed_option_position++];
    if (arguments[optind][seed_option_position] == '\0') {
        optind++;
        seed_option_position = 1;
    }
    program = count > 0 && arguments[0] ? arguments[0] : "getopt";
    spec = strchr(options, option);
    if (option == ':' || spec == NULL) {
        optopt = option;
        if (opterr && options[0] != ':')
            fprintf(stderr, "%s: invalid option -- '%c'\n", program, option);
        return '?';
    }
    if (spec[1] == ':') {
        if (seed_option_position != 1) {
            optarg = arguments[optind] + seed_option_position;
            optind++;
            seed_option_position = 1;
        } else if (optind < count) {
            optarg = arguments[optind++];
        } else {
            optopt = option;
            if (opterr && options[0] != ':')
                fprintf(stderr, "%s: option requires an argument -- '%c'\n", program, option);
            return options[0] == ':' ? ':' : '?';
        }
    }
    return option;
}
