/* Original seed-forth implementation; see LICENSE. C/POSIX locale only. */
#include <locale.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
static char seed_locale_name[] = "C";
static const char *seed_locale_variables[] = {
    "LC_CTYPE", "LC_NUMERIC", "LC_TIME", "LC_COLLATE", "LC_MONETARY", "LC_MESSAGES"
};
static int seed_locale_supported(const char *name)
{
    return !strcmp(name, "C") || !strcmp(name, "POSIX");
}
static const char *seed_locale_environment(int category)
{
    char *name = getenv("LC_ALL");
    if (name && *name) return name;
    name = getenv(seed_locale_variables[category]);
    if (name && *name) return name;
    name = getenv("LANG");
    return name && *name ? name : "C";
}
char *setlocale(int category, const char *locale)
{
    int first;
    int last;
    int index;
    if (category < LC_CTYPE || category > LC_ALL) { errno = EINVAL; return NULL; }
    if (locale == NULL) return seed_locale_name;
    if (*locale) {
        if (seed_locale_supported(locale)) return seed_locale_name;
        errno = EINVAL;
        return NULL;
    }
    first = category == LC_ALL ? LC_CTYPE : category;
    last = category == LC_ALL ? LC_MESSAGES : category;
    for (index = first; index <= last; index++) {
        if (!seed_locale_supported(seed_locale_environment(index))) {
            errno = EINVAL;
            return NULL;
        }
    }
    return seed_locale_name;
}
