#include <stdlib.h>
#include <unistd.h>
#include <locale.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
int main(int argc, char **argv)
{
    char *replacement[] = {"A=first", "AB=other", "EMPTY=", "A=second", NULL};
    char **saved = environ;
    char *result;
    int category;
    if (argc != 2 || environ != argv + argc + 1) return 1;
    if (!getenv("SEED_ENV_TEST") || strcmp(getenv("SEED_ENV_TEST"), "runtime marker")) return 2;
    if (getenv("SEED_ENV") || getenv("SEED_ENV_TEST_MISSING")) return 3;
    environ = replacement;
    errno = EDOM;
    if (strcmp(getenv("A"), "first") || strcmp(getenv("AB"), "other")
        || strcmp(getenv("EMPTY"), "") || getenv("MISSING")
        || getenv("") || getenv("A=first") || errno != EDOM) return 4;
    environ = saved;
    if (strcmp(setlocale(LC_ALL, NULL), "C")) return 5;
    if (strcmp(setlocale(LC_ALL, "POSIX"), "C")) return 6;
    if (setlocale(99, "C") || setlocale(LC_CTYPE, "seed_no_such_locale_20261003")) return 7;
    if (strcmp(setlocale(LC_ALL, NULL), "C")) return 8;
    category = strcmp(argv[1], "all") == 0 ? LC_ALL : LC_CTYPE;
    result = setlocale(category, "");
    printf("%d %s\n", result != NULL, setlocale(category, NULL));
    return 0;
}
