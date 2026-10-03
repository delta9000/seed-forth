/* Integer/string generator formats through unchanged GCC 4.0.4 vasprintf. */
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#if !defined(va_copy) && defined(__va_copy)
#define va_copy(destination, source) __va_copy(destination, source)
#endif

int vasprintf(char **, const char *, va_list);

static int check(const char *expected, const char *format, ...)
{
    va_list list;
    va_list copy;
    char *actual;
    char *again;
    int count;
    int copied_count;
    va_start(list, format);
    va_copy(copy, list);
    count = vasprintf(&actual, format, list);
    copied_count = vasprintf(&again, format, copy);
    va_end(copy);
    va_end(list);
    if (count < 0 || copied_count != count) return 1;
    if (count != (int)strlen(expected)) return 2;
    if (strcmp(actual, expected) || strcmp(again, expected)) return 3;
    free(actual);
    free(again);
    return 0;
}

int main(void)
{
    if (check("", "")) return 1;
    if (check("gt-tree:42: node -> value", "%s:%d: %s -> %s",
              "gt-tree",42,"node","value")) return 2;
    if (check("-17 42 2a 52 A %", "%d %u %x %o %c %%",-17,42U,42U,42U,'A')) return 3;
    if (check("[   00042][abc   ]", "[%8.5d][%-6.3s]",42,"abcdef")) return 4;
    if (check("[    0042][abc   ]", "[%*.*d][%*.*s]",8,4,42,-6,3,"abcdef")) return 5;
    if (check("1:a 2:b 3:c 4:d 5:e 6:f 7:g 8:h 9:i 10:j",
              "%d:%s %d:%s %d:%s %d:%s %d:%s %d:%s %d:%s %d:%s %d:%s %d:%s",
              1,"a",2,"b",3,"c",4,"d",5,"e",6,"f",7,"g",8,"h",9,"i",10,"j")) return 6;
    puts("PASS: original GCC vasprintf integer/string formats, copied lists and GP overflow");
    return 0;
}
