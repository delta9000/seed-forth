/* Original regression fixture; see LICENSE. Linux AMD64 LP64. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#ifdef SPANS_HOST
#include <sys/mman.h>
#else
#include <seed-syscall.h>
#endif
#ifdef SPANS_INTEROP
size_t tested_strspn(const char *, const char *);
char *tested_strpbrk(const char *, const char *);
#define span tested_strspn
#define first tested_strpbrk
#else
#define span strspn
#define first strpbrk
#endif

static unsigned long read_u32(const unsigned char *p)
{
    return (unsigned long)p[0] + ((unsigned long)p[1] << 8)
        + ((unsigned long)p[2] << 16) + ((unsigned long)p[3] << 24);
}

static char *guarded_page(void)
{
#ifdef SPANS_HOST
    char *area = (char *)mmap(0, 12288, PROT_NONE,
                              MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (area == MAP_FAILED) return 0;
    if (mprotect(area + 4096, 4096, PROT_READ | PROT_WRITE)) {
        munmap(area, 12288);
        return 0;
    }
#else
    long mapping = __seed_syscall6(9, 0, 12288, 0, 34, -1, 0);
    char *area;
    if (mapping < 0) return 0;
    area = (char *)mapping;
    if (__seed_syscall6(10, mapping + 4096, 4096, 3, 0, 0, 0)) {
        __seed_syscall6(11, mapping, 12288, 0, 0, 0, 0);
        return 0;
    }
#endif
    return area + 4096;
}

static int release_page(char *page)
{
#ifdef SPANS_HOST
    return munmap(page - 4096, 12288);
#else
    return (int)__seed_syscall6(11, (long)(page - 4096), 12288, 0, 0, 0, 0);
#endif
}

int main(int argc, char **argv)
{
    unsigned char header[16];
    char *text;
    char *reject;
    char *saved_text;
    char *saved_reject;
    char *text_page;
    char *reject_page;
    char *guard_text;
    char *guard_reject;
    FILE *input;
    unsigned long i;
    unsigned long count;
    size_t text_bytes;
    size_t reject_bytes;
    size_t text_length;
    size_t reject_length;
    size_t wanted;
    size_t actual;
    long wanted_pointer;
    char *pointer;
    char *(*find)(const char *, const char *);
    size_t (*function)(const char *, const char *);
    int left;
    int right;
    if (argc != 2 || sizeof(size_t) != 8 || (size_t)-1 < (size_t)1
        || sizeof(span("", "")) != sizeof(size_t)) return 1;
    function = span;
    find = first;
    input = fopen(argv[1], "rb");
    if (!input || fread(header, 1, 4, input) != 4) return 2;
    count = read_u32(header);
    text = malloc(262145);
    reject = malloc(16385);
    saved_text = malloc(262145);
    saved_reject = malloc(16385);
    text_page = guarded_page();
    reject_page = guarded_page();
    if (!text || !reject || !saved_text || !saved_reject
        || !text_page || !reject_page) return 3;
    for (i = 0; i < count; i = i + 1) {
        if (fread(header, 1, 16, input) != 16) return 4;
        text_bytes = read_u32(header);
        reject_bytes = read_u32(header + 4);
        wanted = read_u32(header + 8);
        wanted_pointer = (long)read_u32(header + 12) - 1;
        if (!text_bytes || text_bytes > 262145 || !reject_bytes
            || reject_bytes > 16385) return 5;
        if (fread(text, 1, text_bytes, input) != text_bytes
            || fread(reject, 1, reject_bytes, input) != reject_bytes) return 6;
        if (text[text_bytes - 1] || reject[reject_bytes - 1]) return 7;
        memcpy(saved_text, text, text_bytes);
        memcpy(saved_reject, reject, reject_bytes);
        errno = EDOM;
        actual = function(text, reject);
        pointer = find(text, reject);
        if (actual != wanted || errno != EDOM) return 8;
        if (pointer != (wanted_pointer < 0 ? NULL : text + wanted_pointer)) return 16;
        if (memcmp(text, saved_text, text_bytes)
            || memcmp(reject, saved_reject, reject_bytes)) return 9;
        /* Copy only each true C string, putting its first or last byte at
           a readable page boundary. Both arguments have independent guards. */
        text_length = strlen(text) + 1;
        reject_length = strlen(reject) + 1;
        /* Read-only arguments may alias, including the empty suffix set. */
        if (function(text, text) != text_length - 1
            || function(text, text + text_length - 1) != 0
            || find(text, text) != (text_length == 1 ? NULL : text)
            || find(text, text + text_length - 1) != NULL
            || errno != EDOM) return 15;
        if (text_length <= 4096 && reject_length <= 4096) {
            for (left = 0; left < 2; left = left + 1) {
                for (right = 0; right < 2; right = right + 1) {
                    guard_text = left ? text_page + 4096 - text_length : text_page;
                    guard_reject = right ? reject_page + 4096 - reject_length : reject_page;
                    memcpy(guard_text, text, text_length);
                    memcpy(guard_reject, reject, reject_length);
                    errno = EDOM;
                    if (function(guard_text, guard_reject) != wanted
                        || errno != EDOM) return 10;
                    pointer = find(guard_text, guard_reject);
                    if (pointer != (wanted_pointer < 0 ? NULL : guard_text + wanted_pointer)
                        || errno != EDOM) return 17;
                    if (memcmp(guard_text, text, text_length)
                        || memcmp(guard_reject, reject, reject_length)) return 11;
                }
            }
        }
        printf("%lu %lu %ld\n", i, (unsigned long)actual, wanted_pointer);
    }
    strcpy(text, "abcb");
    if (function(text, text + 1) != 0 || find(text, text + 1) != text + 1
        || function(text + 1, text) != 3 || find(text + 1, text) != text + 1)
        return 18;
    if (fgetc(input) != EOF || ferror(input) || fclose(input)) return 12;
    if (release_page(text_page) || release_page(reject_page)) return 13;
    free(text); free(reject); free(saved_text); free(saved_reject);
#ifdef SPANS_HOST
    /* Reverse-ABI caller uses host FILE handles returned by host fopen.
       Do not mix the private stdout macro with the host FILE representation. */
    return 0;
#else
    return ferror(stdout) ? 14 : 0;
#endif
}
