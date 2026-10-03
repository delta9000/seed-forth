#ifndef SEED_GCC_STDLIB_H
#define SEED_GCC_STDLIB_H
#include <stddef.h>
/* Only implemented interfaces are declared; this is not a complete libc. */
void *malloc(size_t size);
void free(void *pointer);
void *calloc(size_t count, size_t size);
void *realloc(void *pointer, size_t size);
#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#endif
