/* sscanf/fscanf %n: built by the Forth compiler against runtime/gcc-seed
   (production) and by host GCC against glibc (oracle only); the
   scanf-count-check.py driver requires identical output. */
#include <stdio.h>
#include <string.h>

static void four(const char *text)
{
    unsigned int a = 0, b = 0, c = 0, d = 0;
    int n = -1;
    int result = sscanf(text, "%x:%x:%x:%x%n", &a, &b, &c, &d, &n);
    printf("[%s] %d %x %x %x %x n=%d\n", text, result, a, b, c, d, n);
}

int main(int argc, char **argv)
{
    static const char *inputs[] = {
        "500:5:bf:8a3b", "500:5:bf:8a3b:extra", " 1:2:3:4  ", "1:2:3", "", "zz", 0
    };
    int index;
    int n, m, x, y;
    long ln;
    char word[32];
    FILE *stream;
    for (index = 0; inputs[index]; index++) four(inputs[index]);
    n = m = x = y = -1;
    index = sscanf("12 34", "%d%n %n%d", &x, &n, &m, &y);
    printf("%d ", index);
    printf("%d %d %d %d\n", x, n, m, y);
    n = -1;
    index = sscanf("", "%n", &n);
    printf("%d %d\n", index, n);
    n = -1;
    index = sscanf("   ", " %n", &n);
    printf("%d %d\n", index, n);
    n = -1;
    index = sscanf("abcdef", "abc%n", &n);
    printf("%d %d\n", index, n);
    n = -1;
    index = sscanf("abcdef", "abx%n", &n);
    printf("%d %d\n", index, n);
    n = -1;
    index = sscanf("  word rest", "%s%n", word, &n);
    printf("%d %d %s\n", index, n, word);
    ln = -1;
    index = sscanf("7 8", "%d %d%ln", &x, &y, &ln);
    printf("%d %ld\n", index, ln);
    n = -1;
    index = sscanf("5", "%d%n", &x, &n);
    printf("%d %d\n", index, n);
    stream = argc > 1 ? fopen(argv[1], "w+") : NULL;
    if (stream) {
        fputs("  42 tail", stream);
        rewind(stream);
        n = -1;
        index = fscanf(stream, "%d%n", &x, &n);
        printf("fscanf %d %d %d ", index, x, n);
        index = getc(stream);
        printf("next %c\n", index);
        fclose(stream);
    }
    return 0;
}
