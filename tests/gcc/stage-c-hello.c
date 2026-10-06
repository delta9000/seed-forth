/* Stage C hosted program: built by the Forth-built GCC 4.0.4 against the
   musl 1.1.24 and libgcc that compiler built (gcc-direct/stage-c.py).
   Exercises stdio, formatted output, malloc/free, qsort, strtol, string
   functions, long double formatting and a 128-bit division (libgcc's
   __divti3); tests/gcc/stage-c-hello.expected is its exact output.  */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int ti __attribute__((mode(TI)));

static ti divide(ti a, ti b)
{
    return a / b;
}

static int compare(const void *a, const void *b)
{
    int x = *(const int *) a, y = *(const int *) b;
    return (x > y) - (x < y);
}

int main(void)
{
    int values[] = {42, -7, 1000, 3, 0, 19};
    size_t count = sizeof values / sizeof values[0], i;
    char buffer[64], line[64];
    char *copy;
    long long big = 1234567890123LL;
    FILE *file;

    printf("hello from musl\n");
    qsort(values, count, sizeof values[0], compare);
    for (i = 0; i < count; i++)
        printf("%d%c", values[i], i + 1 < count ? ' ' : '\n');
    snprintf(buffer, sizeof buffer, "%s|%5.2f|%-4x|%lld|%lu", "fmt", 3.14159, 255u, big / 7, (unsigned long) count);
    puts(buffer);
    copy = malloc(strlen(buffer) + 1);
    if (!copy)
        return 1;
    strcpy(copy, buffer);
    printf("len %u cmp %d chr %s\n", (unsigned) strlen(copy), strcmp(copy, buffer) == 0, strchr(copy, '|') + 1);
    free(copy);
    printf("strtol %ld %ld\n", strtol("-12345", 0, 10), strtol("0x7f", 0, 0));
    printf("%.3e %g\n", 6.02214076e23, 1.0 / 3.0);
    {
        volatile long long divisor = -97;  /* not foldable: a real __divti3 call */
        ti q = divide((ti) big * 1000000007, (ti) divisor);
        printf("ti %lld %llu\n", (long long) (q >> 64), (unsigned long long) q);
    }
    printf("%.10Lf\n", 1.0L / 7);
    file = tmpfile();
    if (!file)
        return 2;
    fprintf(file, "round %d trip\n", 7);
    rewind(file);
    if (!fgets(line, sizeof line, file))
        return 3;
    fclose(file);
    fputs(line, stdout);
    return 0;
}
