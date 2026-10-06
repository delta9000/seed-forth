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
/* Fixed C-locale text; unlisted numbers give "Unknown error N". */
char *strerror(int number);
/* POSIX helper needed by libiberty consumers. */
char *strdup(const char *string);
/* C/POSIX additions; see ../STRINGS-POSIX.md. Collation is byte order. */
int strcoll(const char *left, const char *right);
size_t strxfrm(char *destination, const char *source, size_t count);
char *strtok(char *string, const char *separators);
char *strtok_r(char *string, const char *separators, char **saved);
size_t strnlen(const char *string, size_t limit);
char *strndup(const char *string, size_t count);
char *stpcpy(char *destination, const char *source);
char *stpncpy(char *destination, const char *source, size_t count);
/* glibc's description ("Hangup", "Real-time signal 3", "Unknown signal
   99"); numbered texts share a static buffer. See ../SIGNALS.md. */
char *strsignal(int number);
#endif
