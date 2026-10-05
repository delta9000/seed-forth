/* Original seed-forth test; see LICENSE and runtime/gcc-seed/DECIMAL-INPUT.md.
   Reads one decimal string per line and prints the binary64 bits of atof. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char line[8192];

int main(void)
{
    double value;
    unsigned long bits;
    size_t length;
    while (fgets(line, sizeof line, stdin)) {
        length = strlen(line);
        if (length && line[length - 1] == '\n') line[--length] = '\0';
        value = atof(line);
        memcpy(&bits, &value, sizeof bits);
        printf("%016lx\n", bits);
    }
    return 0;
}
