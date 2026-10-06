#ifndef SEED_GCC_STRINGS_H
#define SEED_GCC_STRINGS_H
/* Original seed-forth interface; see LICENSE and ../STRINGS-POSIX.md.
   BSD string helpers in the ASCII C locale. */
#include <stddef.h>
/* Case-insensitive comparison of ASCII letters only; bytes compare as
   unsigned char after lower-casing. */
int strcasecmp(const char *left, const char *right);
int strncasecmp(const char *left, const char *right, size_t count);
/* strchr and strrchr under their BSD names. */
char *index(const char *string, int value);
char *rindex(const char *string, int value);
void bzero(void *destination, size_t count);
/* Overlap-safe, like memmove (note the source-first argument order). */
void bcopy(const void *source, void *destination, size_t count);
int bcmp(const void *left, const void *right, size_t count);
/* 1-based index of the least significant set bit; 0 for 0. */
int ffs(int value);
#endif
