#ifndef SEED_GCC_WCTYPE_H
#define SEED_GCC_WCTYPE_H
#include <wchar.h>
/* The two measured Heirloom predicates, fixed ASCII C/POSIX locale. */
int iswprint(wint_t value);
int iswspace(wint_t value);
#endif
