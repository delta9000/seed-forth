#ifndef SEED_GCC_STRING_H
#define SEED_GCC_STRING_H
#include <stddef.h>
void *memcpy(void *destination, const void *source, size_t count);
void *memmove(void *destination, const void *source, size_t count);
void *memset(void *destination, int value, size_t count);
int memcmp(const void *left, const void *right, size_t count);
void *memchr(const void *memory, int value, size_t count);
size_t strlen(const char *string);
size_t strcspn(const char *string, const char *reject);
size_t strspn(const char *string, const char *accept);
char *strpbrk(const char *string, const char *accept);
int strcmp(const char *left, const char *right);
int strncmp(const char *left, const char *right, size_t count);
char *strcpy(char *destination, const char *source);
char *strncpy(char *destination, const char *source, size_t count);
char *strcat(char *destination, const char *source);
char *strncat(char *destination, const char *source, size_t count);
char *strchr(const char *string, int value);
char *strrchr(const char *string, int value);
char *strstr(const char *haystack, const char *needle);
/* POSIX helper needed by libiberty consumers. */
char *strdup(const char *string);
#endif
