/* Original seed-forth implementation; see LICENSE. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
void __assert_fail(const char *expression, const char *file,
                   unsigned int line, const char *function)
{
    if (function)
        fprintf(stderr, "%s:%u: %s: assertion `%s' failed\n",
                file, line, function, expression);
    else
        fprintf(stderr, "%s:%u: assertion `%s' failed\n",
                file, line, expression);
    abort();
}
