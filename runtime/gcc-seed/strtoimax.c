/* Original seed-forth implementation; see LICENSE and STRINGS-POSIX.md.
   LP64: long long, intmax_t and long share one 64-bit range, so the
   long conversion gives exactly the required result and errno. */
#include <stdlib.h>
#include <inttypes.h>

intmax_t strtoimax(const char *text, char **end, int base)
{
    return strtol(text, end, base);
}
