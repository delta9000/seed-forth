#ifndef SEED_GCC_STDLIB_H
#define SEED_GCC_STDLIB_H
#include <stddef.h>
#define MB_CUR_MAX ((size_t)1)
int mbtowc(wchar_t *wide, const char *bytes, size_t count);
int wctomb(char *bytes, wchar_t wide);
/* Only implemented interfaces are declared; this is not a complete libc. */
void *malloc(size_t size);
void free(void *pointer);
void *calloc(size_t count, size_t size);
void *realloc(void *pointer, size_t size);
void qsort(void *base, size_t count, size_t size,
           int (*compare)(const void *, const void *));
void *bsearch(const void *key, const void *base, size_t count, size_t size,
              int (*compare)(const void *, const void *));
/* Fixed ASCII C locale; bases 0 and 2..36, no binary-prefix extension. */
unsigned long strtoul(const char *text, char **end, int base);
long strtol(const char *text, char **end, int base);
int atoi(const char *text);
long atol(const char *text);
/* INT_MIN has no representable positive int result, as in ISO C. */
int abs(int value);
/* Create a 0600 exclusive read/write file by replacing six trailing Xs. */
int mkstemp(char *template);
/* Basename of argv[0], initialized by the runtime-aware entry before main. */
extern char *__progname;
/* Searches the current environ; returns a pointer into that entry. */
char *getenv(const char *name);
/* Inserts STRING itself (not a copy) into a runtime-owned environ vector;
   NAME without '=' removes NAME. See ../ENVIRONMENT.md. */
int putenv(char *string);
/* Terminates the supported single-threaded, unbuffered runtime; no atexit. */
void exit(int status);
void abort(void);
#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#endif
