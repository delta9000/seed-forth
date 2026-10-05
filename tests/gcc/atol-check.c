/* Original seed-forth regression fixture; see LICENSE. Linux AMD64 LP64. */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#ifdef ATOL_HOST
#include <sys/mman.h>
#else
#include <seed-syscall.h>
#endif
#ifdef ATOL_INTEROP
long seed_atol(const char *text);
#define parse seed_atol
#else
#define parse atol
#endif

struct test_case { const char *text; int extension; };
#include "atol-cases.h"

static char *guarded_page(void)
{
#ifdef ATOL_HOST
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
#ifdef ATOL_HOST
    return munmap(page - 4096, 12288);
#else
    return (int)__seed_syscall6(11, (long)(page - 4096), 12288, 0, 0, 0, 0);
#endif
}

int main(void)
{
    unsigned int i;
    int initial_error;
    int observed_error;
    int edge;
    size_t length;
    long value;
    long guarded_value;
    char *page = guarded_page();
    char *text;
    if (!page || sizeof(long) != 8) return 1;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
#ifdef ATOL_LIBC_ORACLE
        /* ISO C does not define atol on unrepresentable values. */
        if (cases[i].extension) continue;
#endif
        length = strlen(cases[i].text) + 1;
        if (length > 4096) return 2;
        for (initial_error = 0; initial_error <= EDOM; initial_error += EDOM) {
            errno = initial_error;
            value = parse(cases[i].text);
            observed_error = errno;
            printf("%u %ld %d\n", i, value, observed_error);
            for (edge = 0; edge < 2; edge++) {
                /* Check both a string immediately after PROT_NONE and a
                 * terminator on the final readable byte before PROT_NONE. */
                text = edge ? page + 4096 - length : page;
                memcpy(text, cases[i].text, length);
                errno = initial_error;
                guarded_value = parse(text);
                if (guarded_value != value || errno != observed_error) return 3;
            }
        }
    }
    if (release_page(page)) return 4;
    return ferror(stdout) ? 5 : 0;
}
