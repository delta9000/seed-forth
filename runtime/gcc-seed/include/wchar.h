#ifndef SEED_GCC_WCHAR_H
#define SEED_GCC_WCHAR_H
#include <stddef.h>
#include <stdio.h>
/* Linux AMD64: wchar_t is signed32-bit; wint_t is unsigned32-bit. */
typedef unsigned int wint_t;
#define WEOF ((wint_t)-1)
wint_t getwc(FILE *stream);
long wcstol(const wchar_t *text, wchar_t **end, int base);
/* Restartable conversions in the stateless ASCII C locale; see ../WIDE.md.
   Bytes above 127 and wide values above 127 fail with EILSEQ. */
typedef struct {
    int __seed_count;
    unsigned int __seed_value;
} mbstate_t;
size_t mbrtowc(wchar_t *wide, const char *bytes, size_t count, mbstate_t *state);
size_t mbrlen(const char *bytes, size_t count, mbstate_t *state);
size_t wcrtomb(char *bytes, wchar_t wide, mbstate_t *state);
int mbsinit(const mbstate_t *state);
wint_t btowc(int byte);
int wctob(wint_t wide);
#endif
