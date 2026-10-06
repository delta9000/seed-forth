/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md. */
#include <string.h>

char *strtok_r(char *string, const char *separators, char **saved)
{
    char *token;
    if (string == NULL) string = *saved;
    if (string == NULL) return NULL;
    string += strspn(string, separators);
    if (*string == '\0') {
        *saved = NULL;
        return NULL;
    }
    token = string;
    string += strcspn(string, separators);
    if (*string) *string++ = '\0';
    else string = NULL;
    *saved = string;
    return token;
}

char *strtok(char *string, const char *separators)
{
    static char *saved;
    return strtok_r(string, separators, &saved);
}
