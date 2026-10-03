#ifndef SEED_GCC_STDLIB_H
#define SEED_GCC_STDLIB_H
#include <stddef.h>
/* Only implemented interfaces are declared; this is not a complete libc. */
void *malloc(size_t size);
void free(void *pointer);
void *calloc(size_t count, size_t size);
void *realloc(void *pointer, size_t size);
void qsort(void *base, size_t count, size_t size,
           int (*compare)(const void *, const void *));
/* Terminates the supported single-threaded, unbuffered runtime; no atexit. */
void exit(int status);
void abort(void);
#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#endif
