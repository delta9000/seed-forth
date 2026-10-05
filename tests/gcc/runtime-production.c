/* The production test is itself compiled by Forth, without host headers. */
#include <stddef.h>
#include <limits.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <seed-syscall.h>

int runtime_types(void)
{
    if (sizeof(char) != 1 || sizeof(short) != 2 || sizeof(int) != 4)
        return 1;
    if (sizeof(long) != 8 || sizeof(void *) != 8 || sizeof(size_t) != 8)
        return 2;
    if (sizeof(ptrdiff_t) != 8 || sizeof(long long) != 8)
        return 3;
    if ((char)255 != -1 || CHAR_BIT != 8 || CHAR_MIN != -128)
        return 4;
    if (ULONG_MAX / 2 != (unsigned long)LONG_MAX)
        return 5;
    return 0;
}

int runtime_memory(void)
{
    unsigned char a[160];
    unsigned char b[160];
    size_t n;
    size_t i;
    for (n = 0; n <= 128; n = n + 1) {
        for (i = 0; i < 160; i = i + 1) {
            a[i] = 0xA5;
            b[i] = (unsigned char)(i * 7);
        }
        if (memcpy(a + 1, b + 3, n) != a + 1)
            return 11;
        if (a[0] != 0xA5 || a[n + 1] != 0xA5)
            return 12;
        if (memcmp(a + 1, b + 3, n) != 0)
            return 13;
        if (memset(a + 1, 0x1F3, n) != a + 1)
            return 14;
        for (i = 1; i <= n; i = i + 1) {
            if (a[i] != 0xF3)
                return 15;
        }
        if (a[0] != 0xA5 || a[n + 1] != 0xA5)
            return 16;
        for (i = 0; i < 160; i = i + 1)
            a[i] = (unsigned char)i;
        memmove(a + 3, a + 1, n);
        for (i = 0; i < n; i = i + 1) {
            if (a[i + 3] != (unsigned char)(i + 1))
                return 17;
        }
        for (i = 0; i < 160; i = i + 1)
            a[i] = (unsigned char)i;
        memmove(a + 1, a + 3, n);
        for (i = 0; i < n; i = i + 1) {
            if (a[i + 1] != (unsigned char)(i + 3))
                return 18;
        }
    }
    a[0] = 255;
    b[0] = 1;
    if (memcmp(a, b, 1) <= 0 || memcmp(b, a, 1) >= 0)
        return 19;
    if (memchr(a, 511, 1) != a || memchr(a, 0, 0) != NULL)
        return 20;
    return 0;
}

int runtime_strings(void)
{
    char a[40];
    char b[8];
    char needle[4];
    char *copy;
    size_t i;
    b[0] = 'a'; b[1] = 'b'; b[2] = 'a'; b[3] = 0;
    needle[0] = 'b'; needle[1] = 'a'; needle[2] = 0;
    memset(a, 0xA5, sizeof(a));
    if (strcpy(a, b) != a || strlen(a) != 3 || strcmp(a, b) != 0)
        return 31;
    if ((unsigned char)a[4] != 0xA5)
        return 32;
    if (strchr(a, 'a') != a || strrchr(a, 'a') != a + 2)
        return 33;
    if (strchr(a, 0) != a + 3 || strrchr(a, 0) != a + 3)
        return 34;
    if (strchr(a, 'z') != NULL || strrchr(a, 'z') != NULL)
        return 35;
    if (strstr(a, needle) != a + 1 || strstr(a, b + 3) != a)
        return 36;
    if (strstr(needle, b) != NULL)
        return 37;
    if (strncpy(a, b, 6) != a)
        return 38;
    for (i = 3; i < 6; i = i + 1) {
        if (a[i] != 0)
            return 39;
    }
    a[2] = 'x';
    strncpy(a, b, 2);
    if (a[2] != 'x' || strncmp(a, b, 2) != 0)
        return 40;
    strcpy(a, b);
    if (strcat(a, needle) != a || strlen(a) != 5)
        return 41;
    if (strncat(a, b, 2) != a || strlen(a) != 7 || a[7] != 0)
        return 42;
    if (strncat(a, b, 0) != a || strlen(a) != 7)
        return 43;
    copy = strdup(a);
    if (copy == NULL || copy == a || strcmp(copy, a) != 0)
        return 44;
    free(copy);
    a[0] = (char)255; a[1] = 0;
    b[0] = 1; b[1] = 0;
    if (strcmp(a, b) <= 0 || strncmp(a, b, 1) <= 0)
        return 45;
    if (strncmp(a, b, 0) != 0)
        return 46;
    return 0;
}

int runtime_allocations(void)
{
    unsigned char *p;
    unsigned char *q;
    unsigned char residency;
    long mapping;
    size_t n;
    size_t i;
    if (errno != 0 || __errno_location() != __errno_location())
        return 51;
    for (n = 0; n <= 129; n = n + 1) {
        errno = EDOM;
        p = malloc(n);
        if (p == NULL || ((unsigned long)p & 15) != 0 || errno != EDOM)
            return 52;
        for (i = 0; i < n; i = i + 1)
            p[i] = (unsigned char)i;
        q = realloc(p, n + 200);
        if (q == NULL || ((unsigned long)q & 15) != 0)
            return 53;
        for (i = 0; i < n; i = i + 1) {
            if (q[i] != (unsigned char)i)
                return 54;
        }
        p = realloc(q, 1);
        if (p == NULL)
            return 55;
        errno = ERANGE;
        free(p);
        free(NULL);
        if (errno != ERANGE)
            return 56;
    }
    p = calloc(257, 17);
    if (p == NULL)
        return 57;
    for (i = 0; i < 257 * 17; i = i + 1) {
        if (p[i] != 0)
            return 58;
    }
    p[0] = 23; p[257 * 17 - 1] = 71;
    errno = 0;
    q = realloc(p, (size_t)-1);
    if (q != NULL || errno != ENOMEM || p[0] != 23 || p[257 * 17 - 1] != 71)
        return 59;
    errno = 0;
    q = realloc(p, (size_t)LONG_MAX - 16);
    if (q != NULL || errno != ENOMEM || p[0] != 23 || p[257 * 17 - 1] != 71)
        return 60;
    if (realloc(p, 0) != NULL)
        return 61;
    errno = 0;
    if (calloc((size_t)-1, 2) != NULL || errno != ENOMEM)
        return 62;
    errno = 0;
    if (calloc(2, (size_t)-1) != NULL || errno != ENOMEM)
        return 63;
    errno = 0;
    if (malloc((size_t)-1) != NULL || errno != ENOMEM)
        return 64;
    p = calloc(0, (size_t)-1);
    q = calloc((size_t)-1, 0);
    if (p == NULL || q == NULL || p == q)
        return 65;
    free(p); free(q);
    p = realloc(NULL, 2049);
    if (p == NULL)
        return 66;
    /* Large allocations retain individual page-aligned mappings.
       mincore must find no mapping after free; no allocation intervenes. */
    mapping = (long)p - 16;
    free(p);
    if (__seed_syscall6(27, mapping, 4096, (long)&residency, 0, 0, 0) != -ENOMEM)
        return 67;
    p = malloc(23);
    if (p == NULL) return 68;
    mapping = (long)p;
    free(p);
    q = malloc(23);
    if (q == NULL || (long)q != mapping) return 69;
    free(q);
    return 0;
}

int runtime_boundaries(void)
{
    long mapped;
    char *area;
    char *end;
    char small[4];
    mapped = __seed_syscall6(9, 0, 8192, 3, 34, -1, 0);
    if (mapped < 0)
        return 71;
    area = (char *)mapped;
    if (__seed_syscall6(10, (long)(area + 4096), 4096, 0, 0, 0, 0) != 0)
        return 72;
    end = area + 4096;
    end[-3] = 'a'; end[-2] = 'b'; end[-1] = 0;
    small[0] = 'a'; small[1] = 'b'; small[2] = 0;
    if (strlen(end - 3) != 2 || strcmp(end - 3, small) != 0)
        return 73;
    if (strncmp(end - 3, small, 99) != 0 || strchr(end - 3, 'z') != NULL)
        return 74;
    if (strrchr(end - 3, 0) != end - 1 || strstr(end - 3, small) != end - 3)
        return 75;
    if (memchr(end - 3, 'z', 3) != NULL || memcmp(end - 3, small, 3) != 0)
        return 76;
    if (memcpy(small, end - 3, 3) != small || memcpy(end - 3, small, 3) != end - 3)
        return 77;
    /* Valid one-past pointers are never dereferenced for zero counts. */
    memcpy(end, end, 0); memmove(end, end, 0); memset(end, 0, 0);
    if (memcmp(end, end, 0) != 0 || memchr(end, 0, 0) != NULL)
        return 78;
    if (strncmp(end, end, 0) != 0 || strncpy(end, end, 0) != end)
        return 79;
    if (__seed_syscall6(11, mapped, 8192, 0, 0, 0, 0) != 0)
        return 80;
    return 0;
}

int main(void)
{
    int result;
    result = runtime_types();
    if (result != 0) return result;
    result = runtime_memory();
    if (result != 0) return result;
    result = runtime_allocations();
    if (result != 0) return result;
    result = runtime_strings();
    if (result != 0) return result;
    return runtime_boundaries();
}
