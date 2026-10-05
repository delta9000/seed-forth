#ifndef SEED_GCC_WCHAR_H
#define SEED_GCC_WCHAR_H
#include <stddef.h>
#include <stdio.h>
/* Linux AMD64: wchar_t is signed32-bit; wint_t is unsigned32-bit. */
typedef unsigned int wint_t;
#define WEOF ((wint_t)-1)
wint_t getwc(FILE *stream);
long wcstol(const wchar_t *text, wchar_t **end, int base);
#endif
