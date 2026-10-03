/* Original seed-forth regression fixture; see LICENSE. */
#include <stdio.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
#include <seed-syscall.h>

static int forwarding(char *buffer, size_t size, const char *format, ...)
{
    va_list original;
    va_list copy;
    char other[256];
    int left;
    int right;
    va_start(original, format);
    va_copy(copy, original);
    left = vsnprintf(buffer, size, format, original);
    right = vsnprintf(other, sizeof(other), format, copy);
    va_end(copy);
    va_end(original);
    if (left != right || strcmp(buffer, other) != 0) return -99;
    return left;
}

static int formats(void)
{
    char buffer[256];
    char tiny[5];
    int n = -1;
    long ln = -1;
    short hn = -1;
    signed char cn = -1;
    long long lln = -1;
    int result;
    long mapping;
    char *edge;
    result = snprintf(buffer, sizeof(buffer), "%s %d %u %ld %lu %llx",
                      "values", INT_MIN, UINT_MAX, LONG_MIN, ULONG_MAX,
                      0xfedcba9876543210ULL);
    if (result != 88 || strcmp(buffer,
        "values -2147483648 4294967295 -9223372036854775808 18446744073709551615 fedcba9876543210") != 0) return 1;
    result = forwarding(buffer, sizeof(buffer), "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
                        1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
    if (result != 20 || strcmp(buffer, "1,2,3,4,5,6,7,8,9,10") != 0) return 2;
    result = snprintf(buffer, sizeof(buffer), "[%+-08d][%#08x][%#.0o][%.0u][%*.*s]",
                      42, 0x2aU, 0U, 0U, -6, 3, "abcdef");
    if (strcmp(buffer, "[+42     ][0x00002a][0][][abc   ]") != 0) return 3;
    if (result != (int)strlen(buffer)) return 4;
    if (snprintf(buffer, sizeof(buffer), "%hhd %hhu %hd %hu %zd %zu %td %jx",
                 255, 511U, 65535, 131071U, -5L, 6UL, -7L, 255UL) != 26) return 5;
    if (strcmp(buffer, "-1 255 -1 65535 -5 6 -7 ff") != 0) return 6;
    if (snprintf(buffer, sizeof(buffer), "abc%n%ln%hn%hhn%llnZ", &n, &ln, &hn, &cn, &lln) != 4) return 7;
    if (n != 3 || ln != 3 || hn != 3 || cn != 3 || lln != 3 || strcmp(buffer, "abcZ")) return 8;
    memset(tiny, 'X', sizeof(tiny));
    if (snprintf(tiny, 4, "abcdef") != 6 || memcmp(tiny, "abc\0X", 5)) return 9;
    if (snprintf(tiny, 1, "abcdef") != 6 || tiny[0] != 0 || tiny[1] != 'b') return 10;
    if (snprintf(NULL, 0, "%s:%d", "abcd", 12) != 7) return 11;
    if (snprintf(buffer, sizeof(buffer), "%p %p", (void *)0x1234, NULL) != 10 || strcmp(buffer, "0x1234 0x0")) return 12;
    if (snprintf(buffer, sizeof(buffer), "%c%c%c", 'A', 0, 'B') != 3 || memcmp(buffer, "A\0B\0", 4)) return 13;
    if (sprintf(buffer, "%#X/%#o/% .3d/%%", 42U, 9U, 7) != 15 || strcmp(buffer, "0X2A/011/ 007/%")) return 14;
    errno = 0;
    if (snprintf(buffer, sizeof(buffer), "ok%f") != -1 || errno != EINVAL || strcmp(buffer, "ok")) return 15;
    errno = 0;
    if (snprintf(buffer, sizeof(buffer), "%ls") != -1 || errno != EINVAL) return 16;
    if (snprintf(NULL, 0, "%2147483647s", "") != INT_MAX) return 17;
    errno = 0;
    if (snprintf(NULL, 0, "x%2147483647s", "") != -1 || errno != 75) return 18;
    errno = 0;
    if (snprintf(buffer, sizeof(buffer), "%2147483648d", 1) != -1 || errno != 75) return 19;
    errno = 0;
    if (snprintf(buffer, sizeof(buffer), "%*d", INT_MIN, 1) != -1 || errno != 75) return 20;
    mapping = __seed_syscall6(9, 0, 8192, 3, 34, -1, 0);
    if (mapping < 0) return 21;
    edge = (char *)mapping + 4093;
    memcpy(edge, "ABC", 3);
    if (__seed_syscall6(10, mapping + 4096, 4096, 0, 0, 0, 0)) return 22;
    if (snprintf(buffer, sizeof(buffer), "%.3s/%.0s", edge, edge + 3) != 4 || strcmp(buffer, "ABC/")) return 23;
    if (__seed_syscall6(11, mapping, 8192, 0, 0, 0, 0)) return 24;
    return 0;
}

int main(int argc, char **argv)
{
    int result;
    FILE *stream;
    char buffer[32];
    result = formats();
    if (result) return result;
    if (argc != 2) return 30;
    stream = fopen(argv[1], "w");
    if (stream == NULL) return 31;
    if (fwrite("abcdefg", 2, 3, stream) != 3 || ftell(stream) != 6) return 32;
    if (fputc(511, stream) != 255 || fputs("\n", stream) < 0) return 33;
    if (fflush(stream) || ferror(stream) || fclose(stream)) return 34;
    stream = fopen(argv[1], "ab");
    if (stream == NULL || fprintf(stream, "%s:%d", "end", 9) != 5 || fclose(stream)) return 35;
    stream = fopen(argv[1], "rb");
    if (stream == NULL || ftell(stream) != 0 || feof(stream) || ferror(stream)) return 36;
    if (getc(stream) != 'a' || ftell(stream) != 1) return 37;
    if (ungetc('Z', stream) != 'Z' || ftell(stream) != 0) return 38;
    if (ungetc('Q', stream) != EOF || getc(stream) != 'Z' || getc(stream) != 'b') return 39;
    if (ungetc('b', stream) != 'b' || fflush(stream) || ftell(stream) != 1 || getc(stream) != 'b') return 40;
    memset(buffer, 0, sizeof(buffer));
    if (fread(buffer, 3, 8, stream) != 3 || memcmp(buffer, "cdef\377\nend:9", 11)) return 41;
    if (!feof(stream) || ferror(stream) || getc(stream) != EOF) return 42;
    if (ungetc(255, stream) != 255 || feof(stream) || getc(stream) != 255 || getc(stream) != EOF) return 43;
    clearerr(stream);
    if (feof(stream) || ferror(stream)) return 44;
    if (fputc('x', stream) != EOF || errno != EBADF || !ferror(stream)) return 45;
    clearerr(stream);
    if (ferror(stream) || fclose(stream)) return 46;
    if (fopen(argv[1], "q") != NULL || errno != EINVAL) return 47;
    if (fopen(argv[1], "r++") != NULL || errno != EINVAL) return 48;
    stream = fopen("/dev/full", "w");
    if (stream == NULL || fprintf(stream, "%d", 7) != -1 || errno != ENOSPC || !ferror(stream)) return 49;
    clearerr(stream);
    if (ferror(stream) || fclose(stream)) return 50;
    if (puts("generator stdio") < 0 || printf("#define %s_CHECK(t)\tTREE_CHECK (t, %s)\n", "PLUS_EXPR", "PLUS_EXPR") != 53) return 51;
    if (putchar('!') != '!' || putc('\n', stdout) != '\n') return 52;
    if (fputs("diagnostic\n", stderr) < 0) return 53;
    errno = ENOENT;
    perror("fixture");
    if (errno != ENOENT) return 54;
    if (fflush(NULL) || fflush(stdout) || ferror(stdout) || fclose(stdout)) return 55;
    if (fputs("", stdout) != EOF || errno != EBADF || !ferror(stdout)) return 56;
    return 0;
}
