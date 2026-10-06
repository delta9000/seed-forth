#ifndef SEED_GCC_CTYPE_H
#define SEED_GCC_CTYPE_H
/* Original seed-forth interface; see LICENSE. Fixed ASCII C locale.
   The supported argument domain is EOF (-1) or an unsigned-char value.
   isascii additionally accepts every int. This measured surface serves
   original oyacc/Heirloom/Flex sources and their ANSI-header probe. */
int isascii(int value);
int isalpha(int value);
int isalnum(int value);
int isdigit(int value);
int isprint(int value);
int iscntrl(int value);
int isgraph(int value);
int ispunct(int value);
int isspace(int value);
int isupper(int value);
int islower(int value);
int isxdigit(int value);
int tolower(int value);
int toupper(int value);
/* Space or tab; see ../STRINGS-POSIX.md. */
int isblank(int value);
#endif
