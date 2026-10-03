/* Independent host-libc oracle. This file is never in the production build. */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <limits.h>
#include <stdint.h>
#include <stddef.h>
int seed_vsnprintf(char *, size_t, const char *, va_list);
int seed_snprintf(char *, size_t, const char *, ...);

static int cases;
static int check(size_t size, const char *format, ...)
{
    char expected[256];
    char actual[256];
    va_list host;
    va_list seed;
    int left;
    int right;
    memset(expected, 0x5a, sizeof(expected));
    memset(actual, 0x5a, sizeof(actual));
    va_start(host, format);
    va_copy(seed, host);
    left = vsnprintf(expected, size, format, host);
    right = seed_vsnprintf(actual, size, format, seed);
    va_end(seed);
    va_end(host);
    cases++;
    if (left != right || memcmp(expected, actual, sizeof(expected))) {
        fprintf(stderr, "case %d, size %zu, format %s: host %d <%s>, seed %d <%s>\n",
                cases, size, format, left, expected, right, actual);
        return 1;
    }
    return 0;
}

int main(void)
{
    const char *signed_formats[] = {"%d", "%+d", "% d", "%08d", "%+08d",
        "% 08d", "%-08d", "%.0d", "%12.8d", "%012.8d", "%-12.8d"};
    const char *unsigned_formats[] = {"%u", "%#o", "%#.0o", "%#08o", "%#.8o",
        "%#x", "%#08x", "%#.0x", "%#12.8X", "%-#12.8x", "%.0u"};
    int signed_values[] = {0, 1, -1, INT_MAX, INT_MIN, 12345, -12345};
    unsigned int unsigned_values[] = {0U, 1U, 8U, 42U, UINT_MAX};
    size_t sizes[] = {0, 1, 2, 5, 256};
    size_t i;
    size_t j;
    size_t k;
    char expected[64];
    char actual[64];
    int hn;
    int sn;
    long hln;
    long sln;
    for (i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        for (j = 0; j < sizeof(signed_formats) / sizeof(signed_formats[0]); j++)
            for (k = 0; k < sizeof(signed_values) / sizeof(signed_values[0]); k++)
                if (check(sizes[i], signed_formats[j], signed_values[k])) return 1;
        for (j = 0; j < sizeof(unsigned_formats) / sizeof(unsigned_formats[0]); j++)
            for (k = 0; k < sizeof(unsigned_values) / sizeof(unsigned_values[0]); k++)
                if (check(sizes[i], unsigned_formats[j], unsigned_values[k])) return 2;
        if (check(sizes[i], "%ld %lu %lld %llu %jx %zd %zu %td", LONG_MIN, ULONG_MAX,
                  LLONG_MIN, ULLONG_MAX, (uintmax_t)UINTMAX_MAX, (long)-9,
                  (size_t)12, (ptrdiff_t)-15)) return 3;
        if (check(sizes[i], "%hhd %hhu %hd %hu", 255, 255, 65535, 65535)) return 4;
        if (check(sizes[i], "[%*.*s][%*s][%.*s]", -12, 4, "generator", 8, "x", 0, "abc")) return 5;
        if (check(sizes[i], "[%*.*d][%*.*x]", -12, -1, -9, 10, 6, 42U)) return 6;
        if (check(sizes[i], "%d%d%d%d%d%d%d%d%d%d", 0, 1, 2, 3, 4, 5, 6, 7, 8, 9)) return 7;
        if (check(sizes[i], "%c%c%c %%", 'A', 0, 'B')) return 8;
        if (check(sizes[i], "%p", (void *)(uintptr_t)0xabcdef123456UL)) return 9;
    }
    hn = -1; sn = -1; hln = -1; sln = -1;
    if (snprintf(expected, 4, "abcde%nZ%ln", &hn, &hln) !=
        seed_snprintf(actual, 4, "abcde%nZ%ln", &sn, &sln)) return 10;
    if (strcmp(expected, actual) || hn != sn || hln != sln || sn != 5 || sln != 6) return 11;
    printf("PASS: %d host-libc formatting comparisons plus truncated %%n counts\n", cases);
    return 0;
}
