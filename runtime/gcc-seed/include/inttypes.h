#ifndef SEED_GCC_INTTYPES_H
#define SEED_GCC_INTTYPES_H
/* Bounded Linux AMD64 LP64 inttypes.h: it supplies the <stdint.h> types
   (first used here for Heirloom lex's intptr_t) and the two string
   conversions, but not the ISO format macros; see ../STDINT.md. */
#include <stdint.h>
/* As strtol/strtoul (intmax_t is long); see ../STRINGS-POSIX.md. */
intmax_t strtoimax(const char *text, char **end, int base);
uintmax_t strtoumax(const char *text, char **end, int base);
#endif
