/* Host libc is an independent oracle; every oracle_* routine is Forth-built. */
#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

void *oracle_memcpy(void *, const void *, size_t);
void *oracle_memmove(void *, const void *, size_t);
void *oracle_memset(void *, int, size_t);
int oracle_memcmp(const void *, const void *, size_t);
void *oracle_memchr(const void *, int, size_t);
size_t oracle_strlen(const char *);
int oracle_strcmp(const char *, const char *);
int oracle_strncmp(const char *, const char *, size_t);
char *oracle_strcpy(char *, const char *);
char *oracle_strncpy(char *, const char *, size_t);
char *oracle_strcat(char *, const char *);
char *oracle_strncat(char *, const char *, size_t);
char *oracle_strchr(const char *, int);
char *oracle_strrchr(const char *, int);
char *oracle_strstr(const char *, const char *);
char *oracle_strdup(const char *);
void *oracle_malloc(size_t);
void oracle_free(void *);
void *oracle_calloc(size_t, size_t);
void *oracle_realloc(void *, size_t);

static int oracle_errno;
int *oracle_errno_location(void) { return &oracle_errno; }

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "runtime oracle failed at line %d: %s\n", __LINE__, #condition); \
    return 1; } } while (0)

static int sign(int value) { return (value > 0) - (value < 0); }

static int memory_cases(void)
{
    unsigned char a[512], b[512], source[512];
    size_t n, from, to, i;
    for (i = 0; i < sizeof(source); ++i)
        source[i] = (unsigned char)(i * 29 + 193);
    for (n = 0; n <= 256; ++n) {
        for (from = 0; from < 8; ++from) {
            for (to = 0; to < 8; ++to) {
                memset(a, 0xa5, sizeof(a)); memset(b, 0xa5, sizeof(b));
                CHECK(oracle_memcpy(a + to, source + from, n) == a + to);
                memcpy(b + to, source + from, n);
                CHECK(memcmp(a, b, sizeof(a)) == 0);
                CHECK(oracle_memset(a + to, 0x17f, n) == a + to);
                memset(b + to, 0x17f, n);
                CHECK(memcmp(a, b, sizeof(a)) == 0);
                memcpy(a, source, sizeof(a)); memcpy(b, source, sizeof(b));
                CHECK(oracle_memmove(a + to, a + from, n) == a + to);
                memmove(b + to, b + from, n);
                CHECK(memcmp(a, b, sizeof(a)) == 0);
            }
            for (i = 0; i < 256; ++i) {
                CHECK(oracle_memchr(source + from, (int)i, n) == memchr(source + from, (int)i, n));
            }
            CHECK(sign(oracle_memcmp(source, source + from, n)) == sign(memcmp(source, source + from, n)));
        }
    }
    return 0;
}

static int string_cases(void)
{
    char input[96], other[96], a[256], b[256];
    size_t n, m, count, i;
    for (n = 0; n < 80; ++n) {
        for (i = 0; i < n; ++i)
            input[i] = (char)(1 + (i * 37 + n) % 255);
        input[n] = 0;
        CHECK(oracle_strlen(input) == strlen(input));
        CHECK(oracle_strcpy(a, input) == a);
        strcpy(b, input);
        CHECK(strcmp(a, b) == 0);
        for (count = 0; count <= n + 2; ++count) {
            memset(a, 0xa5, sizeof(a)); memset(b, 0xa5, sizeof(b));
            CHECK(oracle_strncpy(a, input, count) == a);
            strncpy(b, input, count);
            CHECK(memcmp(a, b, sizeof(a)) == 0);
            strcpy(a, input); strcpy(b, input);
            CHECK(oracle_strncat(a, input, count) == a);
            strncat(b, input, count);
            CHECK(strcmp(a, b) == 0);
        }
        strcpy(a, input); strcpy(b, input);
        CHECK(oracle_strcat(a, input) == a);
        strcat(b, input);
        CHECK(strcmp(a, b) == 0);
        for (i = 0; i <= 511; ++i) {
            CHECK(oracle_strchr(input, (int)i) == strchr(input, (int)i));
            CHECK(oracle_strrchr(input, (int)i) == strrchr(input, (int)i));
        }
        for (m = 0; m < 80; ++m) {
            for (i = 0; i < m; ++i)
                other[i] = (char)(1 + (i * 37 + m) % 255);
            other[m] = 0;
            CHECK(sign(oracle_strcmp(input, other)) == sign(strcmp(input, other)));
            for (count = 0; count <= n + 1; ++count)
                CHECK(sign(oracle_strncmp(input, other, count)) == sign(strncmp(input, other, count)));
            CHECK(oracle_strstr(input, other) == strstr(input, other));
        }
        for (i = 0; i <= n; ++i)
            CHECK(oracle_strstr(input, input + i) == strstr(input, input + i));
        char *copy = oracle_strdup(input);
        CHECK(copy && copy != input && strcmp(copy, input) == 0);
        oracle_free(copy);
    }
    return 0;
}

static int allocation_cases(void)
{
    const size_t sizes[] = {0, 1, 15, 16, 17, 255, 4095, 4096, 4097, 65537};
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
        size_t n = sizes[i];
        oracle_errno = EDOM;
        unsigned char *p = oracle_malloc(n);
        CHECK(p && (uintptr_t)p % 16 == 0 && oracle_errno == EDOM);
        memset(p, 0x93, n);
        unsigned char *q = oracle_realloc(p, n + 4097);
        CHECK(q && (uintptr_t)q % 16 == 0);
        for (size_t j = 0; j < n; ++j) CHECK(q[j] == 0x93);
        oracle_errno = 0;
        CHECK(oracle_realloc(q, SIZE_MAX) == NULL && oracle_errno == ENOMEM);
        for (size_t j = 0; j < n; ++j) CHECK(q[j] == 0x93);
        oracle_errno = ERANGE;
        oracle_free(q);
        CHECK(oracle_errno == ERANGE);
        p = oracle_calloc(n, 7);
        CHECK(p);
        for (size_t j = 0; j < n * 7; ++j) CHECK(p[j] == 0);
        CHECK(oracle_realloc(p, 0) == NULL);
    }
    oracle_errno = 0;
    CHECK(oracle_calloc(SIZE_MAX, 2) == NULL && oracle_errno == ENOMEM);
    oracle_errno = 0;
    CHECK(oracle_calloc(2, SIZE_MAX) == NULL && oracle_errno == ENOMEM);
    oracle_errno = 0;
    CHECK(oracle_malloc((size_t)LONG_MAX - 16) == NULL && oracle_errno == ENOMEM);
    oracle_free(NULL);
    return 0;
}

static int boundary_cases(void)
{
    char *area = mmap(NULL, 8192, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    CHECK(area != MAP_FAILED);
    CHECK(mprotect(area + 4096, 4096, PROT_NONE) == 0);
    for (size_t n = 0; n < 128; ++n) {
        char *s = area + 4095 - n;
        memset(s, 'x', n); s[n] = 0;
        CHECK(oracle_strlen(s) == n);
        CHECK(oracle_strchr(s, 0) == s + n && oracle_strrchr(s, 0) == s + n);
        CHECK(oracle_strchr(s, 'z') == NULL && oracle_strstr(s, "xxz") == NULL);
        CHECK(oracle_strncmp(s, s, n + 2) == 0);
        char *copy = oracle_strdup(s);
        CHECK(copy && strcmp(copy, s) == 0);
        oracle_free(copy);
    }
    CHECK(munmap(area, 8192) == 0);
    return 0;
}

int main(void)
{
    if (memory_cases() || string_cases() || allocation_cases() || boundary_cases())
        return 1;
    puts("PASS: Forth runtime functions match the independent host libc oracle");
    return 0;
}
